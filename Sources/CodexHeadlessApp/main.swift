import AppKit
import CodexHeadlessCore
import Foundation

final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let logger = CHLogger()
    private lazy var configManager = ConfigManager(logger: logger)
    private lazy var stateStore = StateStore(logger: logger)
    private lazy var controller = HeadlessController(
        logger: logger,
        configManager: configManager,
        stateStore: stateStore,
        keepAwakeProcessKind: .app
    )
    private let launchAgentManager = LaunchAgentManager()
    private lazy var hotkeyManager = HotkeyManager(logger: logger)
    private lazy var confirmDialogController = ConfirmDialogController(logger: logger)
    private let restoreOverlayController = RestoreProgressOverlayController()
    private let controllerQueue = DispatchQueue(label: "CodexHeadless.controller-operation")
    private var timer: Timer?
    private var lastHotkeysEnabled: Bool?
    private var controllerOperationInFlight = false

    override init() {
        super.init()
        logger.info("CodexHeadless app started.")
        setupStatusItem()
        configureHotkeysIfNeeded(force: true)
        rebuildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.scheduleRollbackIfNeeded(source: "timer")
            self?.controller.continuePausedRestoreIfReady()
            self?.controller.syncKeepAwakeWithState()
            self?.controller.syncVirtualDisplayState()
            self?.controller.refreshPhaseIfNeeded()
            self?.configureHotkeysIfNeeded()
            self?.syncConfirmDialogWithState()
            self?.syncRestoreOverlayWithState()
            self?.rebuildMenu()
        }
    }

    private func setupStatusItem() {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openMenu)
        updateTitle()
    }

    @objc private func openMenu() {
        rebuildMenu()
        statusItem.button?.performClick(nil)
    }

    private func updateTitle() {
        let state = stateStore.load()
        if RuntimePhaseFormatter.cooldownRemainingSeconds(state) > 0 {
            statusItem.button?.title = "CH: Cooldown"
            return
        }
        let mode = state.mode
        statusItem.button?.title = switch mode {
        case .normal: "CH"
        case .preparing: "CH: Prep"
        case .confirmRequired: "CH: Wait"
        case .headless: "CH: On"
        case .fallback: "CH: Fall"
        case .restoring: "CH: Restoring"
        case .error: "CH: Err"
        }
    }

    private func rebuildMenu() {
        scheduleRollbackIfNeeded(source: "menu")
        updateTitle()

        let state = stateStore.load()
        let config = configManager.load()
        let menu = NSMenu()

        let title = NSMenuItem(title: "CodexHeadless", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        menu.addItem(disabledItem("Mode: \(state.mode.rawValue)"))
        menu.addItem(disabledItem("Keep Awake: \(state.keepAwake ? "On" : "Off")"))
        menu.addItem(disabledItem("Virtual Display: \(state.virtualDisplayCreated ? "Active" : "Inactive")"))
        menu.addItem(disabledItem("Built-in: \(builtInHandlingSummary(state: state))"))
        menu.addItem(disabledItem("Touch Bar: \(state.touchBarHidden == true ? "Hidden" : "Active")"))
        if controllerOperationInFlight {
            menu.addItem(disabledItem("Operation: Running..."))
        }
        addPhaseItems(to: menu, state: state)
        menu.addItem(.separator())

        if state.mode == .confirmRequired {
            menu.addItem(menuItem("Confirm Headless Mode", #selector(confirmHeadless)))
            menu.addItem(disabledItem("Shortcut: ⌃⌥⌘⇧C"))
            menu.addItem(menuItem("Rollback Now", #selector(restoreNormal)))
            menu.addItem(disabledItem("Shortcut: ⌃⌥⌘⇧R"))
            menu.addItem(.separator())
            menu.addItem(disabledItem(autoRollbackText(state: state)))
            menu.addItem(disabledItem("Virtual Display: \(config.virtualDisplay.resolution) @ \(config.virtualDisplay.refreshRate)Hz"))
            menu.addItem(disabledItem("Keep Awake: On"))
        } else {
            menu.addItem(menuItem("Enable Headless Mode", #selector(enableHeadless)))
            menu.addItem(disabledItem("Shortcut: ⌃⌥⌘⇧E"))
            menu.addItem(menuItem("Restore Normal Mode", #selector(restoreNormal)))
            menu.addItem(disabledItem("Shortcut: ⌃⌥⌘⇧R"))
            menu.addItem(.separator())
            menu.addItem(menuItem("Apply Recommended v0.5 Config", #selector(applyRecommendedV05Config)))
            menu.addItem(menuItem("Reset All Settings to Default...", #selector(resetAllSettingsToDefault)))
            menu.addItem(virtualDisplayMenu(config: config))
            menu.addItem(displaySafetyMenu(config: config))
            menu.addItem(menuItem(state.keepAwake ? "Keep Awake: On" : "Keep Awake: Off", #selector(toggleKeepAwake)))
            menu.addItem(keepAwakeBackendMenu(config: config))
            menu.addItem(hotkeysMenu(config: config))
            menu.addItem(confirmDialogMenu(config: config))
            menu.addItem(timingMenu(config: config))
            menu.addItem(menuItem(launchAgentManager.isEnabled() ? "Start at Login: On" : "Start at Login: Off", #selector(toggleStartAtLogin)))
        }

        menu.addItem(.separator())
        menu.addItem(diagnosticsMenu())
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit", #selector(quit)))

        statusItem.menu = menu
    }

    private func virtualDisplayMenu(config: AppConfig) -> NSMenuItem {
        let item = NSMenuItem(title: "Virtual Display", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let currentPolicy = VirtualDisplayPolicy.effectivePolicy(for: config.virtualDisplay)
        submenu.addItem(disabledItem("Policy: \(currentPolicy.rawValue)"))
        submenu.addItem(disabledItem("Resolution: \(config.virtualDisplay.resolution)"))
        submenu.addItem(disabledItem("Scale Mode: \(config.virtualDisplay.scaleMode)"))

        submenu.addItem(.separator())
        for policy in [VirtualDisplayPolicy.auto, .always, .off] {
            let policyItem = NSMenuItem(title: "Policy: \(policy.rawValue)", action: #selector(selectVirtualDisplayPolicy(_:)), keyEquivalent: "")
            policyItem.target = self
            policyItem.representedObject = policy.rawValue
            policyItem.state = policy == currentPolicy ? .on : .off
            submenu.addItem(policyItem)
        }

        submenu.addItem(.separator())
        for scaleMode in [VirtualDisplayScaleMode.standard, .hidpi] {
            let scaleItem = NSMenuItem(title: "Scale: \(scaleMode.rawValue)", action: #selector(selectScaleMode(_:)), keyEquivalent: "")
            scaleItem.target = self
            scaleItem.representedObject = scaleMode.rawValue
            scaleItem.state = scaleMode.rawValue == config.virtualDisplay.scaleMode ? .on : .off
            submenu.addItem(scaleItem)
        }

        submenu.addItem(.separator())
        for preset in ResolutionManager.presets {
            let presetItem = NSMenuItem(title: "Preset: \(preset)", action: #selector(selectPresetResolution(_:)), keyEquivalent: "")
            presetItem.target = self
            presetItem.representedObject = preset.description
            presetItem.state = preset == config.virtualDisplay.resolution ? .on : .off
            submenu.addItem(presetItem)
        }

        submenu.addItem(.separator())
        submenu.addItem(menuItem("Custom Resolution...", #selector(customResolution)))
        item.submenu = submenu
        return item
    }

    private func displaySafetyMenu(config: AppConfig) -> NSMenuItem {
        let item = NSMenuItem(title: "Display & Touch Bar Safety", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for option in [true, false] {
            let title = option ? "Soft Disconnect: On" : "Soft Disconnect: Off"
            let softItem = NSMenuItem(title: title, action: #selector(selectSoftDisconnect(_:)), keyEquivalent: "")
            softItem.target = self
            softItem.representedObject = option
            softItem.state = (config.softDisconnectBuiltInDisplay == true) == option ? .on : .off
            submenu.addItem(softItem)
        }

        submenu.addItem(.separator())
        for option in [true, false] {
            let title = option ? "Touch Bar Hide: On" : "Touch Bar Hide: Off"
            let touchBarItem = NSMenuItem(title: title, action: #selector(selectTouchBarHide(_:)), keyEquivalent: "")
            touchBarItem.target = self
            touchBarItem.representedObject = option
            touchBarItem.state = (config.hideTouchBarInHeadless == true) == option ? .on : .off
            submenu.addItem(touchBarItem)
        }

        if let blockReason = config.softDisconnectBlockedReason {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem("Soft Disconnect Blocked"))
            submenu.addItem(disabledItem(blockReason))
            submenu.addItem(menuItem("Clear Soft Disconnect Block", #selector(clearSoftDisconnectBlock)))
        }

        item.submenu = submenu
        return item
    }

    private func diagnosticsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(menuItem("Copy Status", #selector(copyStatus)))
        submenu.addItem(menuItem("Copy Doctor Report", #selector(copyDoctorReport)))
        submenu.addItem(menuItem("Copy Self Test Report", #selector(copySelfTestReport)))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Open Log", #selector(openLog)))
        submenu.addItem(menuItem("Open Config Folder", #selector(openConfigFolder)))
        item.submenu = submenu
        return item
    }

    private func hotkeysMenu(config: AppConfig) -> NSMenuItem {
        let hotkeys = config.effectiveHotkeys
        let item = NSMenuItem(title: hotkeys.enabled ? "Hotkeys: On" : "Hotkeys: Off", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for option in [true, false] {
            let hotkeyItem = NSMenuItem(title: option ? "Hotkeys: On" : "Hotkeys: Off", action: #selector(selectHotkeysEnabled(_:)), keyEquivalent: "")
            hotkeyItem.target = self
            hotkeyItem.representedObject = option
            hotkeyItem.state = hotkeys.enabled == option ? .on : .off
            submenu.addItem(hotkeyItem)
        }

        submenu.addItem(.separator())
        submenu.addItem(disabledItem("Enable: \(hotkeys.enable.displayString) / \(hotkeyManager.statuses[.enable]?.text ?? "Pending")"))
        submenu.addItem(disabledItem("Confirm: \(hotkeys.confirm.displayString) / \(hotkeyManager.statuses[.confirm]?.text ?? "Pending")"))
        submenu.addItem(disabledItem("Restore: \(hotkeys.restore.displayString) / \(hotkeyManager.statuses[.restore]?.text ?? "Pending")"))

        item.submenu = submenu
        return item
    }

    private func confirmDialogMenu(config: AppConfig) -> NSMenuItem {
        let confirmDialog = config.effectiveConfirmDialog
        let item = NSMenuItem(title: confirmDialog.enabled ? "Confirm Dialog: On" : "Confirm Dialog: Off", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for option in [true, false] {
            let dialogItem = NSMenuItem(title: option ? "Confirm Dialog: On" : "Confirm Dialog: Off", action: #selector(selectConfirmDialogEnabled(_:)), keyEquivalent: "")
            dialogItem.target = self
            dialogItem.representedObject = option
            dialogItem.state = confirmDialog.enabled == option ? .on : .off
            submenu.addItem(dialogItem)
        }

        submenu.addItem(.separator())
        submenu.addItem(disabledItem("Hotkey hints: \(confirmDialog.showHotkeyHints ? "On" : "Off")"))
        submenu.addItem(disabledItem("Countdown: \(confirmDialog.showCountdown ? "On" : "Off")"))
        item.submenu = submenu
        return item
    }

    private func timingMenu(config: AppConfig) -> NSMenuItem {
        let timing = config.effectiveTiming
        let item = NSMenuItem(title: "Timing", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        submenu.addItem(disabledItem("Virtual Display Enumeration: \(timing.virtualDisplayEnumerationWaitSeconds)s"))
        submenu.addItem(disabledItem("Reported ID Extra Wait: \(timing.virtualDisplayReportedIDExtraWaitSeconds)s"))
        submenu.addItem(disabledItem("Soft Disconnect Verify: \(timing.softDisconnectDisappearWaitSeconds)s"))
        submenu.addItem(disabledItem("Restore Built-in Short Wait: \(timing.restoreBuiltInShortWaitSeconds)s"))
        submenu.addItem(disabledItem("Restore Physical Wait: \(timing.restorePhysicalDisplayWaitSeconds)s"))
        submenu.addItem(disabledItem("Restore Grace: \(timing.effectiveRestorePhysicalDisplayGraceSeconds)s"))
        submenu.addItem(disabledItem("Grace Poll Interval: \(timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds)ms"))
        submenu.addItem(disabledItem("Post-promote Stabilization: \(timing.effectiveRestorePostPromoteStabilizationMilliseconds)ms"))
        submenu.addItem(disabledItem("Restore Cooldown: \(timing.restoreCooldownSeconds)s"))
        submenu.addItem(disabledItem("Paused Restore Cooldown: \(timing.restoreCooldownAfterPausedSeconds)s"))

        submenu.addItem(.separator())
        submenu.addItem(timingPresetMenu(
            title: "Restore Physical Display Wait",
            key: "restorePhysicalDisplayWaitSeconds",
            currentValue: timing.restorePhysicalDisplayWaitSeconds,
            presets: [5, 10, 15, 20, 30],
            suffix: "s"
        ))
        submenu.addItem(timingPresetMenu(
            title: "Restore Physical Display Grace",
            key: "restorePhysicalDisplayGraceSeconds",
            currentValue: timing.effectiveRestorePhysicalDisplayGraceSeconds,
            presets: [0, 1, 2, 3, 5],
            suffix: "s"
        ))
        submenu.addItem(timingPresetMenu(
            title: "Grace Poll Interval",
            key: "restorePhysicalDisplayGracePollIntervalMilliseconds",
            currentValue: timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds,
            presets: [100, 250, 500, 1000],
            suffix: "ms"
        ))
        submenu.addItem(timingPresetMenu(
            title: "Post-promote Stabilization",
            key: "restorePostPromoteStabilizationMilliseconds",
            currentValue: timing.effectiveRestorePostPromoteStabilizationMilliseconds,
            presets: [0, 500, 750, 1000, 1500],
            suffix: "ms"
        ))
        submenu.addItem(timingPresetMenu(
            title: "Restore Cooldown",
            key: "restoreCooldownSeconds",
            currentValue: timing.restoreCooldownSeconds,
            presets: [5, 10, 20, 30],
            suffix: "s"
        ))
        submenu.addItem(timingPresetMenu(
            title: "Paused Restore Cooldown",
            key: "restoreCooldownAfterPausedSeconds",
            currentValue: timing.restoreCooldownAfterPausedSeconds,
            presets: [10, 20, 30, 45],
            suffix: "s"
        ))

        submenu.addItem(.separator())
        submenu.addItem(menuItem("Copy Timing Config Debug Info", #selector(copyTimingConfigDebugInfo)))
        submenu.addItem(menuItem("Open Config Folder", #selector(openConfigFolder)))
        submenu.addItem(menuItem("Reset Timing to Default", #selector(resetTimingToDefault)))

        item.submenu = submenu
        return item
    }

    private func timingPresetMenu(
        title: String,
        key: String,
        currentValue: Int,
        presets: [Int],
        suffix: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in presets {
            let label = value == 0 ? "Off" : "\(value)\(suffix)"
            let presetItem = NSMenuItem(title: label, action: #selector(selectTimingPreset(_:)), keyEquivalent: "")
            presetItem.target = self
            presetItem.representedObject = "\(key)=\(value)"
            presetItem.state = value == currentValue ? .on : .off
            submenu.addItem(presetItem)
        }
        submenu.addItem(.separator())
        let customItem = NSMenuItem(title: "Custom...", action: #selector(customTimingValue(_:)), keyEquivalent: "")
        customItem.target = self
        customItem.representedObject = "\(key)|\(currentValue)|\(suffix)|\(title)"
        submenu.addItem(customItem)
        item.submenu = submenu
        return item
    }

    private func keepAwakeBackendMenu(config: AppConfig) -> NSMenuItem {
        let current = config.keepAwakeBackend ?? .caffeinate
        let item = NSMenuItem(title: "Keep Awake Backend", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for backend in [KeepAwakeBackend.caffeinate, .native] {
            let backendItem = NSMenuItem(
                title: backend == .caffeinate ? "caffeinate (CLI-safe)" : "native (App only)",
                action: #selector(selectKeepAwakeBackend(_:)),
                keyEquivalent: ""
            )
            backendItem.target = self
            backendItem.representedObject = backend.rawValue
            backendItem.state = backend == current ? .on : .off
            submenu.addItem(backendItem)
        }

        item.submenu = submenu
        return item
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func builtInHandlingSummary(state: RuntimeState) -> String {
        if state.builtInSoftDisconnected == true {
            return "Soft-disconnected"
        }
        if state.builtInBrightnessDimmed == true {
            return "Dimmed"
        }
        return "Active"
    }

    private func addPhaseItems(to menu: NSMenu, state: RuntimeState) {
        let phase = RuntimePhaseFormatter.phase(state)
        let cooldownRemaining = RuntimePhaseFormatter.cooldownRemainingSeconds(state)
        guard phase != .idle || cooldownRemaining > 0 else {
            return
        }

        menu.addItem(disabledItem("Current Step: \(RuntimePhaseFormatter.message(state))"))
        if let elapsed = RuntimePhaseFormatter.elapsedSeconds(state) {
            menu.addItem(disabledItem("Elapsed: \(elapsed)s"))
        }
        if let remaining = RuntimePhaseFormatter.deadlineRemainingSeconds(state) {
            menu.addItem(disabledItem("Timeout: \(remaining)s"))
        }
        if cooldownRemaining > 0 {
            menu.addItem(disabledItem("Enable available in: \(cooldownRemaining)s"))
        }
        if phase == .restorePaused {
            menu.addItem(disabledItem("The virtual display will stay active until a physical display is available."))
        }
    }

    private func autoRollbackText(state: RuntimeState) -> String {
        guard let deadline = state.rollbackDeadline else {
            return "Auto rollback: Pending"
        }
        let seconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        return "Auto rollback in: \(seconds)s"
    }

    private func configureHotkeysIfNeeded(force: Bool = false) {
        let hotkeys = configManager.load().effectiveHotkeys
        guard force || lastHotkeysEnabled != hotkeys.enabled else {
            return
        }
        lastHotkeysEnabled = hotkeys.enabled
        hotkeyManager.onAction = { [weak self] action in
            self?.handleHotkey(action)
        }
        hotkeyManager.configure(hotkeys)
        logger.info("[Hotkey] Config enabled=\(hotkeys.enabled), enable=\(hotkeys.enable.displayString), confirm=\(hotkeys.confirm.displayString), restore=\(hotkeys.restore.displayString)")
    }

    private func syncConfirmDialogWithState() {
        let state = stateStore.load()
        if state.mode == .confirmRequired {
            let config = configManager.load().effectiveConfirmDialog
            if confirmDialogController.isVisible {
                confirmDialogController.update(deadline: state.rollbackDeadline)
            } else {
                showConfirmDialogIfNeeded(state: state, config: config)
            }
        } else if confirmDialogController.isVisible {
            confirmDialogController.dismiss(reason: "state=\(state.mode.rawValue)")
        }
    }

    private func syncRestoreOverlayWithState() {
        let state = stateStore.load()
        restoreOverlayController.update(state: state)
    }

    private func showConfirmDialogIfNeeded(state: RuntimeState, config: ConfirmDialogConfig) {
        guard state.mode == .confirmRequired, config.enabled else {
            return
        }
        confirmDialogController.show(
            deadline: state.rollbackDeadline,
            config: config,
            onConfirm: { [weak self] in
                self?.handleConfirmRequested(source: "dialog")
            },
            onRollback: { [weak self] in
                self?.handleRestoreRequested(source: "dialog")
            }
        )
    }

    private func handleHotkey(_ action: HotkeyAction) {
        switch action {
        case .enable:
            handleEnableRequested(source: "hotkey")
        case .confirm:
            handleConfirmRequested(source: "hotkey")
        case .restore:
            handleRestoreRequested(source: "hotkey")
        }
    }

    private func handleEnableRequested(source: String) {
        let state = stateStore.load()
        logger.info("[State] enable requested, source=\(source), current=\(state.mode.rawValue)")
        guard state.mode == .normal else {
            logger.warn("[State] enable ignored, source=\(source), current=\(state.mode.rawValue)")
            return
        }
        if let cooldownUntil = state.restoreCooldownUntil,
           cooldownUntil > Date() {
            let remaining = Int(ceil(cooldownUntil.timeIntervalSinceNow))
            logger.warn("[State] enable ignored, source=\(source), restore cooldown active for \(remaining)s")
            showAlert(
                title: "Enable Headless Mode Delayed",
                message: "Normal Mode was just restored. Please wait \(remaining) seconds before enabling Headless Mode again."
            )
            return
        }
        enableHeadlessFromSource(source)
    }

    private func scheduleRollbackIfNeeded(source: String) {
        let state = stateStore.load()
        guard !state.rollbackConfirmed,
              let deadline = state.rollbackDeadline,
              deadline <= Date() else {
            return
        }
        guard !controllerOperationInFlight else {
            return
        }

        runControllerOperation(name: "auto rollback", source: source) { [controller] in
            controller.rollbackIfNeeded()
        }
    }

    private func handleConfirmRequested(source: String) {
        let state = stateStore.load()
        logger.info("[State] confirm requested, source=\(source), current=\(state.mode.rawValue)")
        guard state.mode == .confirmRequired else {
            logger.warn("[State] confirm ignored, source=\(source), current=\(state.mode.rawValue)")
            return
        }
        controller.confirm()
        confirmDialogController.dismiss(reason: "confirmed by \(source)")
        rebuildMenu()
    }

    private func handleRestoreRequested(source: String) {
        let state = stateStore.load()
        logger.info("[State] restore requested, source=\(source), current=\(state.mode.rawValue)")
        switch state.mode {
        case .preparing, .confirmRequired, .headless, .fallback, .restoring, .error:
            confirmDialogController.dismiss(reason: "restored by \(source)")
            runControllerOperation(name: "restore", source: source) { [controller] in
                controller.restoreNormal()
            }
        case .normal:
            logger.info("[State] restore cleanup requested, source=\(source), current=Normal")
            runControllerOperation(name: "restore cleanup", source: source) { [controller] in
                controller.restoreNormal()
            }
        }
    }

    private func enableHeadlessFromSource(_ source: String) {
        runControllerOperation(name: "enable", source: source, operation: { [controller, logger] in
            logger.info("[State] enable accepted, source=\(source)")
            try controller.enableHeadless()
        }, completion: { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success:
                let state = self.stateStore.load()
                self.showConfirmDialogIfNeeded(state: state, config: self.configManager.load().effectiveConfirmDialog)
            case .failure(let error):
                let nsError = error as NSError
                if nsError.domain != "CodexHeadless.VirtualDisplayUnavailable" {
                    self.markError(error)
                } else {
                    self.logger.error(error.localizedDescription)
                }
                self.showAlert(title: "Enable Headless Mode Failed", message: error.localizedDescription)
            }
        })
    }

    private func runControllerOperation(
        name: String,
        source: String,
        operation: @escaping () throws -> Void,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard !controllerOperationInFlight else {
            logger.warn("[State] \(name) ignored, source=\(source), another controller operation is running")
            showAlert(title: "CodexHeadless Is Busy", message: "Another display operation is already running. Please wait for it to finish.")
            return
        }

        controllerOperationInFlight = true
        rebuildMenu()

        controllerQueue.async { [weak self] in
            let result = Result { try operation() }
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.controllerOperationInFlight = false
                completion?(result)
                self.rebuildMenu()
            }
        }
    }

    @objc private func enableHeadless() {
        handleEnableRequested(source: "menu")
    }

    @objc private func restoreNormal() {
        handleRestoreRequested(source: "menu")
    }

    @objc private func confirmHeadless() {
        handleConfirmRequested(source: "menu")
    }

    @objc private func toggleKeepAwake() {
        do {
            let enabled = !stateStore.load().keepAwake
            try controller.setKeepAwake(enabled)
        } catch {
            markError(error)
            showAlert(title: "Keep Awake Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func toggleStartAtLogin() {
        let enable = !launchAgentManager.isEnabled()
        launchAgentManager.setEnabled(enable, executablePath: CommandLine.arguments[0])
        var config = configManager.load()
        config.startAtLogin = enable
        try? configManager.save(config)
        rebuildMenu()
    }

    @objc private func selectPresetResolution(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else {
            return
        }
        do {
            let resolution = try ResolutionManager.parse(rawValue)
            try configManager.setResolution(resolution)
        } catch {
            showAlert(title: "Invalid Resolution", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func selectVirtualDisplayPolicy(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else {
            return
        }
        do {
            try configManager.setVirtualDisplayPolicy(rawValue)
        } catch {
            showAlert(title: "Virtual Display Policy Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func selectScaleMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else {
            return
        }
        do {
            try configManager.setVirtualDisplayScaleMode(rawValue)
        } catch {
            showAlert(title: "Scale Mode Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func selectSoftDisconnect(_ sender: NSMenuItem) {
        guard let enabled = sender.representedObject as? Bool else {
            return
        }
        do {
            try configManager.setSoftDisconnectBuiltInDisplay(enabled)
        } catch {
            showAlert(title: "Soft Disconnect Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func selectTouchBarHide(_ sender: NSMenuItem) {
        guard let enabled = sender.representedObject as? Bool else {
            return
        }
        do {
            try configManager.setHideTouchBarInHeadless(enabled)
        } catch {
            showAlert(title: "Touch Bar Hide Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func selectHotkeysEnabled(_ sender: NSMenuItem) {
        guard let enabled = sender.representedObject as? Bool else {
            return
        }
        do {
            try configManager.setHotkeysEnabled(enabled)
            configureHotkeysIfNeeded(force: true)
        } catch {
            showAlert(title: "Hotkeys Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func selectConfirmDialogEnabled(_ sender: NSMenuItem) {
        guard let enabled = sender.representedObject as? Bool else {
            return
        }
        do {
            try configManager.setConfirmDialogEnabled(enabled)
        } catch {
            showAlert(title: "Confirm Dialog Failed", message: error.localizedDescription)
        }
        if !enabled {
            confirmDialogController.dismiss(reason: "disabled by menu")
        }
        rebuildMenu()
    }

    @objc private func selectTimingPreset(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let separator = rawValue.firstIndex(of: "="),
              let value = Int(rawValue[rawValue.index(after: separator)...]) else {
            return
        }

        let key = String(rawValue[..<separator])
        do {
            try configManager.setTimingValue(key: key, seconds: value)
        } catch {
            showAlert(title: "Timing Update Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func customTimingValue(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else {
            return
        }

        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4,
              let currentValue = Int(parts[1]) else {
            return
        }

        let key = parts[0]
        let suffix = parts[2]
        let title = parts[3]
        let isMilliseconds = key.hasSuffix("Milliseconds")
        let maxValue = isMilliseconds ? 10_000 : 120

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter a custom value in \(suffix). Valid range: 0-\(maxValue)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(string: String(currentValue))
        input.placeholderString = suffix
        input.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                guard let value = Int(input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw NSError(domain: "CodexHeadless.TimingInput", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Enter a whole number from 0 to \(maxValue)."
                    ])
                }
                try configManager.setTimingValue(key: key, seconds: value)
            } catch {
                showAlert(title: "Timing Update Failed", message: error.localizedDescription)
            }
        }
        rebuildMenu()
    }

    @objc private func clearSoftDisconnectBlock() {
        do {
            try configManager.clearSoftDisconnectBlock()
        } catch {
            showAlert(title: "Clear Soft Disconnect Block Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func applyRecommendedV05Config() {
        do {
            try configManager.setResolution(Resolution(width: 2560, height: 1440))
            try configManager.setVirtualDisplayScaleMode(VirtualDisplayScaleMode.hidpi.rawValue)
            try configManager.setVirtualDisplayPolicy(VirtualDisplayPolicy.always.rawValue)
            try configManager.setSoftDisconnectBuiltInDisplay(true)
            try configManager.setHideTouchBarInHeadless(true)
            try configManager.setKeepAwakeBackend(.caffeinate)
        } catch {
            showAlert(title: "Recommended Config Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func resetAllSettingsToDefault() {
        let alert = NSAlert()
        alert.messageText = "Reset All Settings to Default?"
        alert.informativeText = "This resets CodexHeadless configuration to the built-in defaults. It does not change the current runtime state; use Restore Normal Mode if Headless Mode is active."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try configManager.resetConfigToDefault()
            configureHotkeysIfNeeded(force: true)
        } catch {
            showAlert(title: "Reset Defaults Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func selectKeepAwakeBackend(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let backend = KeepAwakeBackend(rawValue: rawValue) else {
            return
        }

        do {
            try configManager.setKeepAwakeBackend(backend)
        } catch {
            showAlert(title: "Keep Awake Backend Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func customResolution() {
        let config = configManager.load()
        let alert = NSAlert()
        alert.messageText = "Custom Resolution"
        alert.informativeText = "Enter width and height for the configured virtual display."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 220, height: 58)

        let widthField = NSTextField(string: String(config.virtualDisplay.resolution.width))
        widthField.placeholderString = "Width"
        let heightField = NSTextField(string: String(config.virtualDisplay.resolution.height))
        heightField.placeholderString = "Height"
        stack.addArrangedSubview(widthField)
        stack.addArrangedSubview(heightField)
        alert.accessoryView = stack

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                guard let width = Int(widthField.stringValue), let height = Int(heightField.stringValue) else {
                    throw ResolutionError.invalidFormat
                }
                let resolution = Resolution(width: width, height: height)
                try ResolutionManager.validate(resolution)
                try configManager.setResolution(resolution)
            } catch {
                showAlert(title: "Invalid Resolution", message: error.localizedDescription)
            }
        }
        rebuildMenu()
    }

    @objc private func openLog() {
        try? CodexHeadlessPaths.ensureDirectories()
        if !FileManager.default.fileExists(atPath: CodexHeadlessPaths.logFile.path) {
            FileManager.default.createFile(atPath: CodexHeadlessPaths.logFile.path, contents: nil)
        }
        NSWorkspace.shared.open(CodexHeadlessPaths.logFile)
    }

    @objc private func openConfigFolder() {
        try? CodexHeadlessPaths.ensureDirectories()
        NSWorkspace.shared.open(CodexHeadlessPaths.supportDirectory)
    }

    @objc private func copyTimingConfigDebugInfo() {
        let timing = configManager.load().effectiveTiming
        let text = """
        virtualDisplayEnumerationWaitSeconds=\(timing.virtualDisplayEnumerationWaitSeconds)
        virtualDisplayReportedIDExtraWaitSeconds=\(timing.virtualDisplayReportedIDExtraWaitSeconds)
        softDisconnectDisappearWaitSeconds=\(timing.softDisconnectDisappearWaitSeconds)
        restoreBuiltInShortWaitSeconds=\(timing.restoreBuiltInShortWaitSeconds)
        restorePhysicalDisplayWaitSeconds=\(timing.restorePhysicalDisplayWaitSeconds)
        restorePhysicalDisplayGraceSeconds=\(timing.effectiveRestorePhysicalDisplayGraceSeconds)
        restorePhysicalDisplayGracePollIntervalMilliseconds=\(timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds)
        restorePostPromoteStabilizationMilliseconds=\(timing.effectiveRestorePostPromoteStabilizationMilliseconds)
        restoreCooldownSeconds=\(timing.restoreCooldownSeconds)
        restoreCooldownAfterPausedSeconds=\(timing.restoreCooldownAfterPausedSeconds)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func resetTimingToDefault() {
        do {
            try configManager.resetTimingToDefault()
        } catch {
            showAlert(title: "Reset Timing Failed", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func copyStatus() {
        let appStatus = appInteractionStatusText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(controller.statusText() + "\n\n" + appStatus, forType: .string)
    }

    @objc private func copyDoctorReport() {
        let doctor = Doctor(configManager: configManager, stateStore: stateStore)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(doctor.report(), forType: .string)
    }

    @objc private func copySelfTestReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SelfTest.report(), forType: .string)
    }

    @objc private func quit() {
        logger.info("CodexHeadless app exiting.")
        NSApp.terminate(nil)
    }

    private func appInteractionStatusText() -> String {
        let config = configManager.load()
        let hotkeys = config.effectiveHotkeys
        let confirmDialog = config.effectiveConfirmDialog
        let countdownText: String
        if let deadline = stateStore.load().rollbackDeadline {
            countdownText = "\(max(0, Int(ceil(deadline.timeIntervalSinceNow))))s"
        } else {
            countdownText = "None"
        }

        return """
        Hotkeys:
          Enabled: \(hotkeys.enabled ? "Yes" : "No")
          Enable: \(hotkeys.enable.displayString) / \(hotkeyManager.statuses[.enable]?.text ?? "Unknown")
          Confirm: \(hotkeys.confirm.displayString) / \(hotkeyManager.statuses[.confirm]?.text ?? "Unknown")
          Restore: \(hotkeys.restore.displayString) / \(hotkeyManager.statuses[.restore]?.text ?? "Unknown")

        Confirm Dialog:
          Enabled: \(confirmDialog.enabled ? "Yes" : "No")
          Visible: \(confirmDialogController.isVisible ? "Yes" : "No")
          Countdown: \(countdownText)
        """
    }

    private func markError(_ error: Error) {
        logger.error(error.localizedDescription)
        stateStore.update { state in
            state.mode = .error
            state.lastError = error.localizedDescription
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
