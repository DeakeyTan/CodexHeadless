import AppKit
import CodexHeadlessCore
import Foundation

final class StatusBarController: NSObject {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let logger = CHLogger()
    lazy var configManager = ConfigManager(logger: logger)
    lazy var stateStore = StateStore(logger: logger)
    lazy var recoveryJournalStore = RecoveryJournalStore(logger: logger)
    lazy var controller = HeadlessController(
        logger: logger,
        configManager: configManager,
        stateStore: stateStore,
        recoveryJournalStore: recoveryJournalStore,
        keepAwakeProcessKind: .app
    )
    let launchAgentManager = LaunchAgentManager()
    lazy var hotkeyManager = HotkeyManager(logger: logger)
    lazy var confirmDialogController = ConfirmDialogController(logger: logger)
    let restoreOverlayController = RestoreProgressOverlayController()
    let presenter = AppStatePresenter()
    let cleanNormalCache = CleanNormalAssessmentCache()
    let operationalEvidenceCache = OperationalEvidenceCache()
    lazy var operationalEvidenceAssessor = OperationalEvidenceAssessor(
        stateStore: stateStore,
        journalStore: recoveryJournalStore,
        sleepManager: SleepManager(stateStore: stateStore, recoveryJournalStore: recoveryJournalStore),
        virtualManager: VirtualDisplayManager(stateStore: stateStore, recoveryJournalStore: recoveryJournalStore),
        displayManager: DisplayManager()
    )
    let confirmDialogRestoreSuppression = ConfirmDialogRestoreSuppression()
    let safetyAssessmentQueue = DispatchQueue(label: "CodexHeadless.safety-assessment", qos: .utility)
    let maintenancePolicy = PeriodicMaintenancePolicy()
    var lastNormalAssessmentUptime: TimeInterval?
    var lastHeadlessReconcileUptime: TimeInterval?
    var transientOperationTitle: String?
    lazy var operationCoordinator = ControllerOperationCoordinator(logger: logger) { [weak self] in
        self?.requestMenuRefresh()
    }

    func terminationBlockReason() -> String? {
        AppTerminationGate.blockReason(AppTerminationSnapshot(
            state: stateStore.load(),
            recoveryJournalActive: FileManager.default.fileExists(atPath: CodexHeadlessPaths.recoveryJournalFile.path),
            operationBusy: operationCoordinator.isBusy
        ))
    }
    var timer: Timer?
    var lastHotkeysEnabled: Bool?
    var pendingRestoreSource: String?
    var lastMenuSignature: String?
    var menuRefreshScheduled = false
    var replacementLossSuspect: ReplacementLossSuspect?
    var replacementLossConfirmationScheduled = false
    var replacementLossRestoreSubmitted = false
    var expectedOperationalOperationID: String?

    override init() {
        super.init()
        DiagnosticLoggingPolicy.shared.setEnabled(false)
        DiagnosticLoggingPolicy.shared.setEnabled(configManager.load().effectiveDiagnosticLoggingEnabled)
        logger.info("CodexHeadless app started.")
        setupStatusItem()
        configureHotkeysIfNeeded(force: true)
        rebuildMenu()
        if stateStore.load().mode == .normal { handleVerifiedNormalTransition(reason: "launch") }
        else { refreshOperationalEvidence(source: .launch) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.schedulePeriodicMaintenance()
            self?.configureHotkeysIfNeeded()
            self?.syncConfirmDialogWithState()
            self?.syncRestoreOverlayWithState()
            self?.rebuildMenu()
        }
    }

    func setupStatusItem() {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openMenu)
        updateTitle()
    }

    @objc func openMenu() {
        rebuildMenu()
        statusItem.button?.performClick(nil)
    }

    func updateTitle() {
        statusItem.button?.title = transientOperationTitle ?? presenter.statusTitle(for: stateStore.load())
    }

    func rebuildMenu() {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            let elapsed = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            if elapsed > 50 { logger.warn("[Perf] menu-rebuild durationMs=\(elapsed)") }
        }
        updateTitle()
        let state = stateStore.load()
        let config = configManager.load()
        synchronizeDiagnosticLoggingPolicy(with: config)
        let configHealth = configManager.health()
        let cached = cleanNormalCache.snapshot()
        let cachedAssessment = cached.usableAssessment(now: Date(), maximumAge: 35)
        let availability = MenuActionAvailability.make(
            state: state,
            configHealthy: configHealth.isHealthy,
            operationBusy: operationCoordinator.isBusy,
            cleanNormal: cachedAssessment?.isClean == true
        )
        if statusItem.menu == nil {
            statusItem.menu = buildStaticMenu(config: config)
        }
        refreshPersistentMenuItems(state: state)
        let operational = state.mode == .normal
            ? OperationalSafetyPresentation.makeNormal(cachedAssessment)
            : OperationalSafetyPresentation.make(
                state: state,
                availability: operationalEvidenceCache.availability(
                    now: Date(), maximumAge: operationalEvidenceMaximumAge(for: state.mode),
                    runtimeMode: state.mode, operationID: expectedOperationalOperationID
                )
            )
        menuItem(id: "safety")?.title = "Safety: \(operational.title)"
        refreshMenuVisibility(state: state, availability: availability, config: config)

        let menuEncoder = JSONEncoder()
        menuEncoder.outputFormatting = [.sortedKeys]
        let configData = try? menuEncoder.encode(config)
        let signature = configData.flatMap { String(data: $0, encoding: .utf8) } ?? "config-unavailable"
        if signature != lastMenuSignature {
            lastMenuSignature = signature
            refreshSettingsSubmenus(config: config)
        }
    }

    func requestMenuRefresh() {
        guard !menuRefreshScheduled else { return }
        menuRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.menuRefreshScheduled = false
            self.rebuildMenu()
        }
    }

    func synchronizeDiagnosticLoggingPolicy(with config: AppConfig) {
        let desired = config.effectiveDiagnosticLoggingEnabled
        let current = DiagnosticLoggingPolicy.shared.isEnabled

        guard desired != current else {
            return
        }

        if desired {
            DiagnosticLoggingPolicy.shared.setEnabled(true)
            logger.info("[Logging] Diagnostic logging enabled after configuration change.")
        } else {
            logger.info("[Logging] Diagnostic logging disabled after configuration change.")
            DiagnosticLoggingPolicy.shared.setEnabled(false)
        }
    }

    func refreshCleanNormalCache(reason: String) {
        guard cleanNormalCache.beginRefresh() else { return }
        lastNormalAssessmentUptime = ProcessInfo.processInfo.systemUptime
        requestMenuRefresh()
        safetyAssessmentQueue.async { [weak self] in
            guard let self else { return }
            let started = DispatchTime.now().uptimeNanoseconds
            let assessment = self.controller.assessCleanNormal()
            let elapsed = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            self.logger.info("[Perf] clean-normal durationMs=\(elapsed) processSnapshots=1 classification=\(assessment.classification.rawValue) reason=\(reason)")
            let previous = self.cleanNormalCache.complete(assessment)
            if self.stateStore.load().mode == .normal {
                if let transition = CleanNormalTransitionDiagnostic.message(
                    previous: previous, current: assessment, source: reason, durationMilliseconds: elapsed
                ) {
                    self.logger.info(transition)
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.lastNormalAssessmentUptime = ProcessInfo.processInfo.systemUptime
                self?.requestMenuRefresh()
            }
        }
    }

    func refreshOperationalEvidence(source: OperationalEvidenceSource) {
        guard operationalEvidenceCache.beginRefresh() else { return }
        requestMenuRefresh()
        safetyAssessmentQueue.async { [weak self] in
            guard let self else { return }
            let started = DispatchTime.now().uptimeNanoseconds
            let evidence = self.operationalEvidenceAssessor.assess(source: source)
            self.completeOperationalEvidence(evidence)
            let elapsed = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            self.logger.info("[Perf] operational-evidence durationMs=\(elapsed) processSnapshots=1 displayEnumerations=1 source=\(source.rawValue)")
            DispatchQueue.main.async { [weak self] in self?.requestMenuRefresh() }
        }
    }

    func completeOperationalEvidence(_ evidence: OperationalEvidence) {
        let previous = operationalEvidenceCache.complete(evidence)
        let state = stateStore.load()
        let currentPresentation = OperationalSafetyPresentation.make(state: state, availability: .fresh(evidence))
        let previousPresentation = previous.map { previousEvidence -> OperationalSafetyPresentation in
            var previousState = state
            previousState.mode = previousEvidence.runtimeMode
            return OperationalSafetyPresentation.make(state: previousState, availability: .fresh(previousEvidence))
        }
        if let message = OperationalTransitionDiagnostic.message(previous: previous, current: evidence, previousPresentation: previousPresentation, currentPresentation: currentPresentation) { logger.info(message) }
        DispatchQueue.main.async { [weak self] in
            self?.expectedOperationalOperationID = evidence.operationID
            self?.handleReplacementContinuity(evidence)
            self?.requestMenuRefresh()
        }
    }

    func handleVerifiedNormalTransition(reason: String) {
        operationalEvidenceCache.clear()
        expectedOperationalOperationID = nil
        replacementLossSuspect = nil
        replacementLossConfirmationScheduled = false
        replacementLossRestoreSubmitted = false
        refreshCleanNormalCache(reason: reason)
    }

    private func operationalEvidenceMaximumAge(for mode: HeadlessMode) -> TimeInterval {
        switch mode { case .preparing, .restoring: 3; case .confirmRequired: 10; case .headless, .fallback: 15; case .error, .recoveryRequired: 30; case .normal: 0 }
    }

    private func buildStaticMenu(config: AppConfig) -> NSMenu {
        let menu = NSMenu()
        let title = NSMenuItem(title: "CodexHeadless", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        for (id, label) in [("mode", "Mode"), ("safety", "Safety: Checking..."), ("keep-awake", "Keep Awake"), ("virtual-display", "Virtual Display"), ("replacement", "Replacement"), ("built-in", "Built-in"), ("touch-bar", "Touch Bar"), ("operation", "Operation: Running...")] {
            menu.addItem(statusItem(label, id: id))
        }
        for index in 0..<6 { menu.addItem(statusItem("", id: "phase-\(index)")) }
        menu.addItem(.separator())
        menu.addItem(identifiedMenuItem("Confirm Headless Mode", #selector(confirmHeadless), id: "confirm"))
        menu.addItem(statusItem("Shortcut: ⌃⌥⌘⇧C", id: "confirm-shortcut"))
        menu.addItem(identifiedMenuItem("Rollback Now", #selector(restoreNormal), id: "rollback"))
        menu.addItem(statusItem("Shortcut: ⌃⌥⌘⇧R", id: "rollback-shortcut"))
        menu.addItem(statusItem("Auto rollback", id: "rollback-countdown"))
        menu.addItem(statusItem("Virtual Display", id: "confirm-virtual"))
        menu.addItem(statusItem("Keep Awake: On", id: "confirm-keep-awake"))
        menu.addItem(identifiedMenuItem("Enable Headless Mode", #selector(enableHeadless), id: "enable"))
        menu.addItem(statusItem("Shortcut: ⌃⌥⌘⇧E", id: "enable-shortcut"))
        menu.addItem(identifiedMenuItem("Restore Normal Mode", #selector(restoreNormal), id: "restore"))
        menu.addItem(statusItem("Shortcut: ⌃⌥⌘⇧R", id: "restore-shortcut"))
        menu.addItem(.separator())
        menu.addItem(identified(configurationProfilesMenu(), id: "profiles"))
        menu.addItem(identifiedMenuItem("Reset All Settings to Default...", #selector(resetAllSettingsToDefault), id: "reset-settings"))
        menu.addItem(identified(virtualDisplayMenu(config: config), id: "virtual-settings"))
        menu.addItem(identified(displaySafetyMenu(config: config), id: "display-safety"))
        menu.addItem(identifiedMenuItem("Keep Awake", #selector(toggleKeepAwake), id: "toggle-keep-awake"))
        menu.addItem(identified(keepAwakeBackendMenu(config: config), id: "keep-awake-backend"))
        menu.addItem(identified(hotkeysMenu(config: config), id: "hotkeys"))
        menu.addItem(identified(confirmDialogMenu(config: config), id: "confirmation"))
        menu.addItem(identified(timingMenu(config: config), id: "timing"))
        menu.addItem(identifiedMenuItem("Start at Login", #selector(toggleStartAtLogin), id: "start-at-login"))
        menu.addItem(.separator())
        let diagnostics = diagnosticsMenu()
        let loggingItem = identifiedMenuItem("Enable Diagnostic Logging", #selector(toggleDiagnosticLogging), id: "diagnostic-logging")
        loggingItem.state = config.effectiveDiagnosticLoggingEnabled ? .on : .off
        diagnostics.submenu?.insertItem(loggingItem, at: 0)
        diagnostics.submenu?.insertItem(.separator(), at: 1)
        menu.addItem(diagnostics)
        menu.addItem(.separator())
        menu.addItem(identifiedMenuItem("Quit", #selector(quit), id: "quit"))
        return menu
    }

    func statusItem(_ title: String, id: String) -> NSMenuItem {
        let item = disabledItem(title)
        item.identifier = NSUserInterfaceItemIdentifier("CodexHeadless.\(id)")
        return item
    }

    func refreshPersistentMenuItems(state: RuntimeState) {
        guard let menu = statusItem.menu else { return }
        let update: (String, String) -> Void = { id, title in
            let identifier = NSUserInterfaceItemIdentifier("CodexHeadless.\(id)")
            menu.items.first { $0.identifier == identifier }?.title = title
        }
        update("mode", "Mode: \(state.mode.rawValue)")
        update("keep-awake", "Keep Awake: \(state.keepAwake ? "On" : "Off")")
        update("virtual-display", "Virtual Display: \(state.virtualDisplayCreated ? "Active" : "Inactive")")
        update("built-in", "Built-in: \(presenter.builtInHandling(for: state))")
        update("touch-bar", "Touch Bar: \(state.touchBarHidden == true ? "Hidden" : "Active")")
        if let replacementType = state.replacementDisplayType {
            let ready = state.replacementDisplayReady == true ? "Ready" : "Preparing"
            let promoted = state.replacementDisplayPromoted == true ? ", Main" : ""
            update("replacement", "Replacement: \(replacementType) / \(ready)\(promoted)")
        }
        menuItem(id: "replacement")?.isHidden = state.replacementDisplayType == nil
        menuItem(id: "operation")?.isHidden = !operationCoordinator.isBusy
        let lines = presenter.phaseLines(for: state)
        for index in 0..<6 {
            let item = menuItem(id: "phase-\(index)")
            item?.title = index < lines.count ? lines[index] : ""
            item?.isHidden = index >= lines.count
        }
    }

    private func refreshMenuVisibility(state: RuntimeState, availability: MenuActionAvailability, config: AppConfig) {
        let dynamic = MenuDynamicPresentation.make(state: state, operationBusy: operationCoordinator.isBusy, now: Date())
        let confirming = dynamic.showsConfirmationActions
        for id in ["confirm", "confirm-shortcut", "rollback", "rollback-shortcut", "rollback-countdown", "confirm-virtual", "confirm-keep-awake"] { menuItem(id: id)?.isHidden = !confirming }
        for id in ["enable", "enable-shortcut", "restore", "restore-shortcut", "profiles", "reset-settings", "virtual-settings", "display-safety", "toggle-keep-awake", "keep-awake-backend", "hotkeys", "confirmation", "timing", "start-at-login"] { menuItem(id: id)?.isHidden = confirming }
        menuItem(id: "enable")?.isEnabled = availability.canEnable
        menuItem(id: "toggle-keep-awake")?.isEnabled = availability.canToggleKeepAwake
        menuItem(id: "toggle-keep-awake")?.title = state.keepAwake ? "Keep Awake: On" : "Keep Awake: Off"
        menuItem(id: "start-at-login")?.title = launchAgentManager.isEnabled() ? "Start at Login: On" : "Start at Login: Off"
        menuItem(id: "quit")?.isEnabled = availability.canQuit && terminationBlockReason() == nil
        menuItem(id: "rollback-countdown")?.title = presenter.autoRollbackText(for: state)
        menuItem(id: "confirm-virtual")?.title = "Virtual Display: \(config.virtualDisplay.resolution) @ \(config.virtualDisplay.refreshRate)Hz"
    }

    private func refreshSettingsSubmenus(config: AppConfig) {
        nestedMenuItem(id: "diagnostic-logging")?.state = config.effectiveDiagnosticLoggingEnabled ? .on : .off
        let policy = VirtualDisplayPolicy.effectivePolicy(for: config.virtualDisplay)
        nestedMenuItem(id: "virtual-policy-summary")?.title = "Policy: \(policy.rawValue)"
        nestedMenuItem(id: "virtual-resolution-summary")?.title = "Resolution: \(config.virtualDisplay.resolution)"
        nestedMenuItem(id: "virtual-scale-summary")?.title = "Scale Mode: \(config.virtualDisplay.scaleMode)"
        let timing = config.effectiveTiming
        let timingTitles: [String: String] = [
            "timing-virtual-enumeration": "Virtual Display Enumeration: \(timing.virtualDisplayEnumerationWaitSeconds)s",
            "timing-reported-id": "Reported ID Extra Wait: \(timing.virtualDisplayReportedIDExtraWaitSeconds)s",
            "timing-soft-disconnect": "Soft Disconnect Verify: \(timing.softDisconnectDisappearWaitSeconds)s",
            "timing-built-in": "Restore Built-in Short Wait: \(timing.restoreBuiltInShortWaitSeconds)s",
            "timing-physical": "Restore Physical Wait: \(timing.restorePhysicalDisplayWaitSeconds)s",
            "timing-grace": "Restore Grace: \(timing.effectiveRestorePhysicalDisplayGraceSeconds)s",
            "timing-poll": "Grace Poll Interval: \(timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds)ms",
            "timing-stabilization": "Post-promote Stabilization: \(timing.effectiveRestorePostPromoteStabilizationMilliseconds)ms",
            "timing-cooldown": "Restore Cooldown: \(timing.restoreCooldownSeconds)s",
            "timing-paused-cooldown": "Paused Restore Cooldown: \(timing.restoreCooldownAfterPausedSeconds)s"
        ]
        for (id, title) in timingTitles { nestedMenuItem(id: id)?.title = title }
        menuItem(id: "hotkeys")?.title = config.effectiveHotkeys.enabled ? "Hotkeys: On" : "Hotkeys: Off"
        menuItem(id: "confirmation")?.title = "Confirmation: \(config.effectiveConfirmation.policy.rawValue)"
        nestedMenuItem(id: "confirmation-timeout-summary")?.title = "Timeout: \(config.effectiveConfirmation.timeoutSeconds)s"
        nestedMenuItem(id: "confirmation-warning")?.isHidden = config.effectiveConfirmation.policy != .never
        let blocked = config.softDisconnectBlockedReason != nil
        nestedMenuItem(id: "soft-block-title")?.isHidden = !blocked
        nestedMenuItem(id: "soft-block-reason")?.isHidden = !blocked
        nestedMenuItem(id: "soft-block-reason")?.title = config.softDisconnectBlockedReason ?? ""
        nestedMenuItem(id: "soft-block-clear")?.isHidden = !blocked

        for item in allMenuItems() {
            switch item.action {
            case #selector(selectVirtualDisplayPolicy(_:)):
                item.state = (item.representedObject as? String) == policy.rawValue ? .on : .off
            case #selector(selectScaleMode(_:)):
                item.state = (item.representedObject as? String) == config.virtualDisplay.scaleMode ? .on : .off
            case #selector(selectPresetResolution(_:)):
                item.state = (item.representedObject as? String) == config.virtualDisplay.resolution.description ? .on : .off
            case #selector(selectSoftDisconnect(_:)):
                item.state = (item.representedObject as? Bool) == (config.softDisconnectBuiltInDisplay == true) ? .on : .off
            case #selector(selectTouchBarHide(_:)):
                item.state = (item.representedObject as? Bool) == (config.hideTouchBarInHeadless == true) ? .on : .off
            case #selector(selectHotkeysEnabled(_:)):
                item.state = (item.representedObject as? Bool) == config.effectiveHotkeys.enabled ? .on : .off
            case #selector(selectConfirmationPolicy(_:)):
                item.state = (item.representedObject as? String) == config.effectiveConfirmation.policy.rawValue ? .on : .off
            case #selector(selectConfirmationTimeout(_:)):
                item.state = (item.representedObject as? Int) == config.effectiveConfirmation.timeoutSeconds ? .on : .off
            case #selector(selectConfirmDialogEnabled(_:)):
                item.state = (item.representedObject as? Bool) == config.effectiveConfirmDialog.enabled ? .on : .off
            case #selector(selectSoftDisconnectFailureBehavior(_:)):
                item.state = (item.representedObject as? String) == config.effectiveDisplayHandoff.onSoftDisconnectFailure.rawValue ? .on : .off
            case #selector(selectKeepAwakeBackend(_:)):
                item.state = (item.representedObject as? String) == KeepAwakeBackend.caffeinate.rawValue ? .on : .off
            case #selector(selectTimingPreset(_:)):
                if let raw = item.representedObject as? String,
                   let separator = raw.firstIndex(of: "="),
                   let value = Int(raw[raw.index(after: separator)...]) {
                    item.state = timingValue(key: String(raw[..<separator]), timing: timing) == value ? .on : .off
                }
            case #selector(customTimingValue(_:)):
                if let raw = item.representedObject as? String {
                    let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
                    if parts.count == 4, let current = timingValue(key: String(parts[0]), timing: timing) {
                        item.representedObject = "\(parts[0])|\(current)|\(parts[2])|\(parts[3])"
                    }
                }
            default: break
            }
        }
    }

    @objc private func toggleDiagnosticLogging() {
        let enabled = !configManager.load().effectiveDiagnosticLoggingEnabled
        runSettingsMutation(name: "set-diagnostic-logging", failureTitle: "Diagnostic Logging Failed", mutation: { [configManager, logger] in
            try configManager.setDiagnosticLoggingEnabled(enabled)
            if enabled {
                DiagnosticLoggingPolicy.shared.setEnabled(true)
                logger.info("[Logging] Diagnostic logging enabled.")
            } else {
                logger.info("[Logging] Diagnostic logging disabled.")
                DiagnosticLoggingPolicy.shared.setEnabled(false)
            }
        })
    }

    private func menuItem(id: String) -> NSMenuItem? {
        statusItem.menu?.items.first { $0.identifier?.rawValue == "CodexHeadless.\(id)" }
    }

    private func nestedMenuItem(id: String) -> NSMenuItem? {
        allMenuItems().first { $0.identifier?.rawValue == "CodexHeadless.\(id)" }
    }

    private func allMenuItems() -> [NSMenuItem] {
        func flatten(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { item in [item] + (item.submenu.map(flatten) ?? []) }
        }
        return statusItem.menu.map(flatten) ?? []
    }

    private func timingValue(key: String, timing: TimingConfig) -> Int? {
        switch key {
        case "virtualDisplayEnumerationWaitSeconds": timing.virtualDisplayEnumerationWaitSeconds
        case "virtualDisplayReportedIDExtraWaitSeconds": timing.virtualDisplayReportedIDExtraWaitSeconds
        case "softDisconnectDisappearWaitSeconds": timing.softDisconnectDisappearWaitSeconds
        case "restoreBuiltInShortWaitSeconds": timing.restoreBuiltInShortWaitSeconds
        case "restorePhysicalDisplayWaitSeconds": timing.restorePhysicalDisplayWaitSeconds
        case "restorePhysicalDisplayGraceSeconds": timing.effectiveRestorePhysicalDisplayGraceSeconds
        case "restorePhysicalDisplayGracePollIntervalMilliseconds": timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds
        case "restoreCooldownSeconds": timing.restoreCooldownSeconds
        case "restoreCooldownAfterPausedSeconds": timing.restoreCooldownAfterPausedSeconds
        case "restorePostPromoteStabilizationMilliseconds": timing.effectiveRestorePostPromoteStabilizationMilliseconds
        default: nil
        }
    }

    func identified(_ item: NSMenuItem, id: String) -> NSMenuItem {
        item.identifier = NSUserInterfaceItemIdentifier("CodexHeadless.\(id)")
        return item
    }

    private func identifiedMenuItem(_ title: String, _ action: Selector, id: String) -> NSMenuItem {
        identified(menuItem(title, action), id: id)
    }


}
