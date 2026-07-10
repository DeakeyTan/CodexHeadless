import Foundation

public final class HeadlessController {
    private let logger: CHLogger
    private let configManager: ConfigManager
    private let stateStore: StateStore
    private let sleepManager: SleepManager
    private let displayManager: DisplayManager
    private let displayLayoutStore: DisplayLayoutStore
    private let builtInDisplayManager: BuiltInDisplayManager
    private let virtualDisplayManager: VirtualDisplayManager
    private let touchBarManager: TouchBarManager
    private let rollbackGuard: RollbackGuard

    public init(
        logger: CHLogger = CHLogger(),
        configManager: ConfigManager = ConfigManager(),
        stateStore: StateStore = StateStore(),
        sleepManager: SleepManager? = nil,
        displayManager: DisplayManager = DisplayManager(),
        displayLayoutStore: DisplayLayoutStore? = nil,
        builtInDisplayManager: BuiltInDisplayManager = BuiltInDisplayManager(),
        virtualDisplayManager: VirtualDisplayManager = VirtualDisplayManager(),
        touchBarManager: TouchBarManager = TouchBarManager(),
        rollbackGuard: RollbackGuard? = nil,
        keepAwakeProcessKind: KeepAwakeProcessKind = .cli
    ) {
        self.logger = logger
        self.configManager = configManager
        self.stateStore = stateStore
        self.sleepManager = sleepManager ?? SleepManager(
            logger: logger,
            stateStore: stateStore,
            configManager: configManager,
            processKind: keepAwakeProcessKind
        )
        self.displayManager = displayManager
        self.displayLayoutStore = displayLayoutStore ?? DisplayLayoutStore(logger: logger)
        self.builtInDisplayManager = builtInDisplayManager
        self.virtualDisplayManager = virtualDisplayManager
        self.touchBarManager = touchBarManager
        self.rollbackGuard = rollbackGuard ?? RollbackGuard(stateStore: stateStore, logger: logger)
    }

    public func enableHeadless(resolutionOverride: Resolution? = nil, rollbackEnabled: Bool = true) throws {
        logger.info("[Enable] requested.")
        rollbackIfNeeded()

        var state = stateStore.load()
        if isUsableHeadlessState(state) {
            logger.info("Headless Mode is already active; skipping duplicate display and brightness operations.")
            return
        }
        if let cooldownUntil = state.restoreCooldownUntil,
           cooldownUntil > Date() {
            let remaining = Int(ceil(cooldownUntil.timeIntervalSinceNow))
            throw NSError(domain: "CodexHeadless.RestoreCooldown", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Normal Mode was just restored. Please wait \(remaining) seconds before enabling Headless Mode again."
            ])
        }

        let enableAlreadyPreparedByApp = state.mode == .preparing
        state.mode = .preparing
        state.lastError = nil
        state.restoreCooldownUntil = nil
        state.activeResolutionOverride = resolutionOverride
        state.originalBrightness = builtInDisplayManager.currentBrightness()
        state.phase = .startingKeepAwake
        state.phaseMessage = RuntimePhase.startingKeepAwake.message
        state.phaseStartedAt = Date()
        state.phaseDeadlineAt = nil
        state.lastProgressAt = Date()
        state.builtInDisplayID = nil
        state.builtInWasMain = nil
        state.replacementDisplayID = nil
        state.replacementDisplayType = nil
        state.replacementDisplayReady = false
        state.replacementDisplayPromoted = false
        state.confirmationRequired = false
        if !enableAlreadyPreparedByApp {
            state.enableCancellationRequested = false
        }
        try stateStore.save(state)

        let config = configManager.load()
        let timing = config.effectiveTiming
        let resolution = resolutionOverride ?? config.virtualDisplay.resolution
        let virtualDisplayPolicy = VirtualDisplayPolicy.effectivePolicy(for: config.virtualDisplay)
        try virtualDisplayManager.validateResolution(resolution)
        logger.info("Requested virtual display resolution: \(resolution) @ \(config.virtualDisplay.refreshRate)Hz, policy=\(virtualDisplayPolicy.rawValue).")

        setPhase(.startingKeepAwake)
        try sleepManager.enableKeepAwake()

        setPhase(.checkingDisplays)
        let displays = displayManager.displays()
        logger.info("Displays before headless: \(displays.map { "\($0.id):\($0.typeLabel):\($0.width)x\($0.height):main=\($0.isMain)" }.joined(separator: ", "))")
        displayLayoutStore.saveCurrentLayout(
            displayManager: displayManager,
            reason: "before entering Headless Mode"
        )

        let builtInDisplay = displays.first { $0.isBuiltIn }
        let builtInDisplayID = builtInDisplay?.id
        let existingExternalDisplayID = displayManager.preferredExternalDisplay()?.id
        let hasExternal = displayManager.hasAlternativeDisplay()
        stateStore.update { runtime in
            runtime.builtInDisplayID = builtInDisplayID
            runtime.builtInWasMain = builtInDisplay?.isMain
        }

        // Prepare: create and validate a replacement while the built-in display stays available.
        var virtualDisplayID: UInt32?
        let shouldCreateVirtualDisplay = virtualDisplayPolicy == .always || (virtualDisplayPolicy == .auto && !hasExternal)
        if shouldCreateVirtualDisplay {
            do {
                virtualDisplayID = try createSoftwareVirtualDisplay(resolution: resolution, config: config)
            } catch {
                let message = "Unable to create a usable virtual display. Normal Mode has been preserved."
                logger.error("[VirtualDisplay] failed to create a usable replacement display: \(error.localizedDescription)")
                cleanFailedEnable(message: message)
                throw NSError(domain: "CodexHeadless.VirtualDisplayUnavailable", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: message
                ])
            }
            if virtualDisplayID != nil {
                setPhase(.validatingVirtualDisplay)
            }
        } else {
            logger.info(hasExternal
                ? "[VirtualDisplay] existing physical replacement is available; managed display is not required."
                : "[VirtualDisplay] policy is off; no virtual display will be created.")
        }

        // A virtual host must not steal main-display status during preparation.
        if builtInDisplay?.isMain == true,
           let builtInDisplayID,
           displayManager.display(id: builtInDisplayID)?.isMain == false {
            let restoredBuiltInMain = (try? displayManager.setMainDisplay(
                id: builtInDisplayID,
                reason: "built-in display during preparation"
            )) == true
            guard restoredBuiltInMain,
                  displayManager.display(id: builtInDisplayID)?.isMain == true else {
                let message = "The built-in display could not remain the main display during preparation. Normal Mode has been preserved."
                cleanFailedEnable(message: message)
                throw NSError(domain: "CodexHeadless.DisplayHandoff", code: 6, userInfo: [NSLocalizedDescriptionKey: message])
            }
            logger.info("[Display] built-in display \(builtInDisplayID) remains main during preparation.")
        } else if builtInDisplay?.isMain == true, let builtInDisplayID {
            logger.info("[Display] built-in display \(builtInDisplayID) remains main during preparation.")
        }

        let replacementDisplayID: UInt32?
        let replacementType: String?
        let usedManagedVirtualDisplay: Bool
        if let existingExternalDisplayID {
            replacementDisplayID = existingExternalDisplayID
            replacementType = "external"
            usedManagedVirtualDisplay = false
            setPhase(.preparingExternalDisplay)
            logger.info("[Display] external replacement ready, displayID=\(existingExternalDisplayID).")
        } else if let virtualDisplayID {
            replacementDisplayID = virtualDisplayID
            replacementType = "managedVirtual"
            usedManagedVirtualDisplay = true
            logger.info("[VirtualDisplay] replacement display ready, displayID=\(virtualDisplayID).")
        } else {
            replacementDisplayID = nil
            replacementType = nil
            usedManagedVirtualDisplay = false
        }

        guard let replacementDisplayID else {
            let message = "Unable to create a usable replacement display. Normal Mode has been preserved."
            logger.error("[Safety] built-in display remained active and main.")
            cleanFailedEnable(message: message)
            throw NSError(domain: "CodexHeadless.VirtualDisplayUnavailable", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        setPhase(.replacementDisplayReady)
        stateStore.update { runtime in
            runtime.replacementDisplayID = replacementDisplayID
            runtime.replacementDisplayType = replacementType
            runtime.replacementDisplayReady = true
        }

        if stateStore.load().enableCancellationRequested == true {
            let message = "Enable was cancelled by a Restore request. Normal Mode has been preserved."
            logger.info("[Enable] cancelled before display handoff commit.")
            cleanFailedEnable(message: message)
            throw NSError(domain: "CodexHeadless.EnableCancelled", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        // Commit: promotion and soft-disconnect intentionally run back-to-back.
        setPhase(.committingDisplayHandoff)
        logger.info("[Display] committing handoff to \(replacementType ?? "replacement") display \(replacementDisplayID).")
        let promotedExternal: Bool
        do {
            if usedManagedVirtualDisplay {
                promotedExternal = try displayManager.setMainDisplay(
                    id: replacementDisplayID,
                    reason: "managed virtual display",
                    fallbackResolution: resolution
                )
            } else {
                promotedExternal = try displayManager.setMainDisplay(
                    id: replacementDisplayID,
                    reason: "external/dummy display"
                )
            }
        } catch {
            let message = "Unable to set the replacement display as the main display. Normal Mode has been preserved."
            abortFailedHandoff(message: message, builtInDisplayID: builtInDisplayID, softDisconnected: false)
            throw NSError(domain: "CodexHeadless.DisplayHandoff", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard promotedExternal else {
            let message = "Unable to set the replacement display as the main display. Normal Mode has been preserved."
            abortFailedHandoff(message: message, builtInDisplayID: builtInDisplayID, softDisconnected: false)
            throw NSError(domain: "CodexHeadless.DisplayHandoff", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
        stateStore.update { $0.replacementDisplayPromoted = true }

        setPhase(.disconnectingBuiltInDisplay)
        logger.info("[Display] soft-disconnecting built-in display \(builtInDisplayID.map(String.init) ?? "unknown").")
        let softDisconnectResult = builtInDisplayManager.attemptSoftDisconnectIfSafe(
            builtInDisplayID: builtInDisplayID,
            hasAlternativeDisplay: hasExternal || promotedExternal,
            enabled: config.softDisconnectBuiltInDisplay == true
        )
        let softDisconnected = softDisconnectResult.success
        if softDisconnected {
            logger.info(softDisconnectResult.message)
            setPhase(.waitingForBuiltInDisplayDisconnect, timeoutSeconds: timing.softDisconnectDisappearWaitSeconds)
            if let builtInDisplayID,
               displayManager.waitForDisplay(
                   id: builtInDisplayID,
                   present: false,
                   timeoutSeconds: TimeInterval(timing.softDisconnectDisappearWaitSeconds)
               ) {
                logger.info("Built-in display \(builtInDisplayID) disappeared from display enumeration after soft-disconnect.")
            } else if let builtInDisplayID {
                logger.warn("Built-in display \(builtInDisplayID) is still visible after \(timing.softDisconnectDisappearWaitSeconds)s soft-disconnect verification wait.")
            }
        } else if config.softDisconnectBuiltInDisplay == true {
            logger.warn(softDisconnectResult.message)
            if softDisconnectResult.crashed {
                do {
                    try configManager.blockSoftDisconnect(reason: softDisconnectResult.message)
                } catch {
                    logger.error("Failed to block soft-disconnect after helper crash: \(error.localizedDescription)")
                }
            }

            if config.effectiveDisplayHandoff.onSoftDisconnectFailure == .restore {
                let message = "The built-in display could not be disconnected. Normal Mode has been restored."
                abortFailedHandoff(message: message, builtInDisplayID: builtInDisplayID, softDisconnected: false)
                throw NSError(domain: "CodexHeadless.DisplayHandoff", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }

        var brightnessDimmed = false
        var brightnessMethod: String?
        if !softDisconnected {
            let brightnessResult = builtInDisplayManager.dimBuiltInDisplay()
            brightnessDimmed = brightnessResult.success
            brightnessMethod = brightnessResult.success ? brightnessResult.method : nil
            if brightnessResult.success {
                logger.info(brightnessResult.message)
            } else {
                logger.warn(brightnessResult.message)
            }
        }

        setPhase(.verifyingDisplayHandoff)
        let replacementStillUsable = displayManager.displays().contains {
            $0.id == replacementDisplayID && $0.isActive && ($0.isOnline || $0.isManagedVirtual)
        }
            || (usedManagedVirtualDisplay && stateStore.load().virtualDisplayPID != nil)
        if !replacementStillUsable {
            let message = "The replacement display became unavailable during handoff. Normal Mode has been restored."
            abortFailedHandoff(message: message, builtInDisplayID: builtInDisplayID, softDisconnected: softDisconnected)
            throw NSError(domain: "CodexHeadless.DisplayHandoff", code: 4, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let headlessReady = promotedExternal && (softDisconnected || brightnessDimmed)
        if !headlessReady {
            let message = "The built-in display could not be safely handed off. Normal Mode has been restored."
            abortFailedHandoff(message: message, builtInDisplayID: builtInDisplayID, softDisconnected: softDisconnected)
            throw NSError(domain: "CodexHeadless.DisplayHandoff", code: 5, userInfo: [NSLocalizedDescriptionKey: message])
        }
        let touchBarResult: TouchBarChangeResult
        if headlessReady {
            setPhase(.hidingTouchBar)
            touchBarResult = touchBarManager.hideIfEnabled(config.hideTouchBarInHeadless == true)
            if touchBarResult.success {
                logger.info(touchBarResult.message)
            } else if config.hideTouchBarInHeadless == true {
                logger.warn(touchBarResult.message)
            }
        } else {
            touchBarResult = .skipped("Touch Bar hide skipped because Headless Mode is not ready.")
            if config.hideTouchBarInHeadless == true {
                logger.warn(touchBarResult.message)
            }
        }

        sleepManager.applyDisplaySleepFast()

        state = stateStore.load()
        state.keepAwake = true
        state.virtualDisplayCreated = virtualDisplayID != nil || state.virtualDisplayCreated
        state.virtualDisplayID = virtualDisplayID ?? state.virtualDisplayID
        state.builtInBrightnessDimmed = brightnessDimmed
        state.builtInBrightnessMethod = brightnessMethod
        state.builtInSoftDisconnected = softDisconnected
        state.builtInSoftDisconnectMethod = softDisconnected ? softDisconnectResult.method : nil
        state.softDisconnectedDisplayID = softDisconnected ? builtInDisplayID : nil
        state.builtInSoftDisconnectLastMessage = softDisconnectResult.message
        state.externalDisplayPromoted = promotedExternal
        state.touchBarHidden = touchBarResult.success
        state.touchBarHideMethod = touchBarResult.success ? touchBarResult.method : nil
        state.touchBarLastMessage = touchBarResult.message
        if !softDisconnected && !brightnessDimmed {
            state.lastError = "Built-in display is still active; brightness control was unavailable."
        }
        let confirmation = config.effectiveConfirmation
        let confirmationRequired = headlessReady
            && rollbackEnabled
            && confirmation.policy.requiresConfirmation(usedManagedVirtualDisplay: usedManagedVirtualDisplay)
        state.confirmationRequired = confirmationRequired
        if headlessReady {
            state.mode = confirmationRequired ? .confirmRequired : .headless
        } else {
            state.mode = .fallback
        }
        state.phase = state.mode == .confirmRequired ? .waitingForConfirmation : .headlessActive
        state.phaseMessage = state.phase?.message
        state.phaseStartedAt = Date()
        state.phaseDeadlineAt = confirmationRequired
            ? Date().addingTimeInterval(TimeInterval(confirmation.timeoutSeconds))
            : nil
        state.lastProgressAt = Date()
        state.rollbackConfirmed = !confirmationRequired
        if confirmationRequired {
            state.rollbackDeadline = Date().addingTimeInterval(TimeInterval(confirmation.timeoutSeconds))
        } else {
            state.rollbackDeadline = nil
        }
        try stateStore.save(state)

        if confirmationRequired {
            _ = rollbackGuard.begin(timeoutSeconds: confirmation.timeoutSeconds)
        }

        logger.info("[Display] handoff completed.")
        logger.info("[Confirmation] policy=\(confirmation.policy.rawValue), required=\(confirmationRequired).")
        logger.info("Headless Mode entered with mode \(state.mode.rawValue). External promoted: \(promotedExternal).")
    }

    public func restoreNormal() {
        logger.info("Restore Normal Mode requested.")
        rollbackGuard.cancel()

        let state = stateStore.load()
        if state.mode == .normal,
           state.keepAwake == false,
           state.virtualDisplayCreated == false,
           state.builtInSoftDisconnected != true,
           state.builtInBrightnessDimmed != true,
           state.touchBarHidden != true {
            stateStore.update { newState in
                newState.phase = .idle
                newState.phaseMessage = RuntimePhase.idle.message
                newState.phaseStartedAt = Date()
                newState.phaseDeadlineAt = nil
                newState.lastProgressAt = Date()
            }
            logger.info("Normal Mode is already restored.")
            return
        }

        let timing = configManager.load().effectiveTiming
        let restoringAfterPaused = state.phase == .restorePaused || state.mode == .error
        stateStore.update { newState in
            newState.mode = .restoring
        }
        setPhase(.restoringBuiltInDisplay)

        if state.builtInSoftDisconnected == true {
            let restoreDisplayResult = builtInDisplayManager.restoreBuiltInDisplay(displayID: state.softDisconnectedDisplayID)
            if restoreDisplayResult.success {
                logger.info(restoreDisplayResult.message)
                setPhase(.waitingForPhysicalDisplay, timeoutSeconds: timing.restoreBuiltInShortWaitSeconds)
                if let displayID = state.softDisconnectedDisplayID,
                   displayManager.waitForDisplay(
                       id: displayID,
                       present: true,
                       timeoutSeconds: TimeInterval(timing.restoreBuiltInShortWaitSeconds)
                   ) {
                    logger.info("Built-in display \(displayID) reappeared in display enumeration after restore.")
                } else if let displayID = state.softDisconnectedDisplayID {
                    logger.warn("Built-in display \(displayID) did not reappear during \(timing.restoreBuiltInShortWaitSeconds)s short restore wait.")
                }
            } else {
                logger.warn(restoreDisplayResult.message)
            }
        }

        setPhase(.waitingForPhysicalDisplay, timeoutSeconds: timing.restorePhysicalDisplayWaitSeconds)
        logger.info("[Phase] waitingForPhysicalDisplay, shortWait=\(timing.restoreBuiltInShortWaitSeconds)s, maxWait=\(timing.restorePhysicalDisplayWaitSeconds)s")
        var restoreDisplay = displayManager.waitForRestorePriorityDisplay(
            managedVirtualDisplayID: state.virtualDisplayID,
            timeoutSeconds: TimeInterval(timing.restorePhysicalDisplayWaitSeconds)
        )
        if restoreDisplay == nil {
            logger.warn("Physical display was not enumerated before primary timeout; entering final grace polling.")
            restoreDisplay = waitForRestorePriorityDisplayDuringGrace(
                managedVirtualDisplayID: state.virtualDisplayID,
                timing: timing
            )
        }

        guard restoreDisplay != nil else {
            logger.warn("Physical display still unavailable after grace polling; entering paused restore and keeping managed virtual display alive for safety.")
            stateStore.update { newState in
                newState.mode = .restoring
                newState.phase = .restorePaused
                newState.phaseMessage = RuntimePhase.restorePaused.message
                newState.phaseStartedAt = Date()
                newState.phaseDeadlineAt = nil
                newState.lastProgressAt = Date()
                newState.lastError = "Restore paused while waiting for a physical display."
                newState.rollbackDeadline = nil
                newState.rollbackConfirmed = true
            }
            return
        }

        if let restoreDisplay {
            logger.info("Physical display became available: displayID=\(restoreDisplay.id)")
        }
        finishRestoreAfterPhysicalDisplayAvailable(state: state, afterPausedRestore: restoringAfterPaused)
    }

    public func continuePausedRestoreIfReady() {
        let state = stateStore.load()
        guard state.mode == .restoring,
              state.phase == .restorePaused,
              displayManager.restorePriorityDisplay(managedVirtualDisplayID: state.virtualDisplayID) != nil else {
            return
        }

        logger.info("Paused restore resumed after a physical display became available.")
        finishRestoreAfterPhysicalDisplayAvailable(state: state, afterPausedRestore: true)
    }

    private func finishRestoreAfterPhysicalDisplayAvailable(state: RuntimeState, afterPausedRestore: Bool) {
        let timing = configManager.load().effectiveTiming
        setPhase(.promotingPhysicalDisplay)
        do {
            if let restoreDisplay = displayManager.restorePriorityDisplay(managedVirtualDisplayID: state.virtualDisplayID),
               restoreDisplay.isMain {
                setPhase(.keepingExternalDisplayAsMain)
                logger.info("Keeping physical display as main display: \(restoreDisplay.id)")
            } else {
                try displayManager.setMainDisplayToRestorePriority(managedVirtualDisplayID: state.virtualDisplayID)
            }
            restoreSavedDisplayLayout(managedVirtualDisplayID: state.virtualDisplayID)
        } catch {
            logger.warn("Failed to restore preferred main display before virtual display cleanup: \(error.localizedDescription)")
        }

        let stabilizationSeconds = Double(timing.effectiveRestorePostPromoteStabilizationMilliseconds) / 1000.0
        if stabilizationSeconds > 0 {
            logger.info("Waiting \(timing.effectiveRestorePostPromoteStabilizationMilliseconds)ms after physical display promotion before closing virtual display.")
            Thread.sleep(forTimeInterval: stabilizationSeconds)
        }

        setPhase(.restoringTouchBar)
        let touchBarResult = touchBarManager.showIfNeeded(state.touchBarHidden)
        if touchBarResult.success {
            logger.info(touchBarResult.message)
        } else if state.touchBarHidden == true {
            logger.warn(touchBarResult.message)
        }

        setPhase(.restoringBrightness)
        let restoreResult = builtInDisplayManager.restoreBrightness(state.originalBrightness)
        if restoreResult.success {
            logger.info(restoreResult.message)
        } else {
            logger.warn(restoreResult.message)
        }

        setPhase(.stoppingVirtualDisplay)
        virtualDisplayManager.destroyVirtualDisplayIfManaged()

        setPhase(.stoppingKeepAwake)
        sleepManager.disableKeepAwake()
        let cooldownSeconds = afterPausedRestore ? timing.restoreCooldownAfterPausedSeconds : timing.restoreCooldownSeconds
        let cooldownUntil = Date().addingTimeInterval(TimeInterval(cooldownSeconds))

        stateStore.update { newState in
            Self.resetRuntimeState(&newState, lastError: nil, cooldownUntil: cooldownUntil)
            newState.phase = .coolingDown
            newState.phaseMessage = RuntimePhase.coolingDown.message
            newState.phaseStartedAt = Date()
            newState.phaseDeadlineAt = cooldownUntil
            newState.lastProgressAt = Date()
        }
        let suffix = afterPausedRestore ? " after paused restore" : ""
        logger.info("Normal Mode restored\(suffix). Enable cooldown until \(ISO8601DateFormatter().string(from: cooldownUntil)), duration=\(cooldownSeconds)s.")
    }

    private func waitForRestorePriorityDisplayDuringGrace(
        managedVirtualDisplayID: UInt32?,
        timing: TimingConfig
    ) -> DisplayInfo? {
        let graceSeconds = timing.effectiveRestorePhysicalDisplayGraceSeconds
        guard graceSeconds > 0 else {
            logger.info("Final grace polling is disabled.")
            return nil
        }

        let pollIntervalMilliseconds = max(50, timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds)
        let deadline = Date().addingTimeInterval(TimeInterval(graceSeconds))
        stateStore.update { state in
            state.phase = .waitingForPhysicalDisplay
            state.phaseMessage = "Final check for a physical display..."
            state.phaseStartedAt = Date()
            state.phaseDeadlineAt = deadline
            state.lastProgressAt = Date()
        }
        logger.info("[Phase] waitingForPhysicalDisplay, grace=\(graceSeconds)s, pollInterval=\(pollIntervalMilliseconds)ms")

        while Date() < deadline {
            if let display = displayManager.restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID) {
                logger.info("Physical display became available during grace polling; continuing restore without entering paused state.")
                return display
            }
            Thread.sleep(forTimeInterval: Double(pollIntervalMilliseconds) / 1000.0)
        }

        return displayManager.restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID)
    }

    private func restoreSavedDisplayLayout(managedVirtualDisplayID: UInt32?) {
        logger.info("Displays before saved layout restore: \(displayManager.compactStatus())")
        do {
            let snapshot = try displayLayoutStore.loadMatching(displays: displayManager.displays())
            let result = try displayManager.restoreLayout(
                from: snapshot,
                managedVirtualDisplayID: managedVirtualDisplayID
            )
            logger.info(result.message)
            logger.info("Displays after saved layout restore: \(displayManager.compactStatus())")
        } catch {
            logger.warn("Saved display layout restore skipped: \(error.localizedDescription)")
        }
    }

    @discardableResult
    public func confirm() -> Bool {
        let state = stateStore.load()
        guard state.mode == .confirmRequired else {
            logger.info("Confirm ignored: current mode is \(state.mode.rawValue).")
            return false
        }
        rollbackGuard.confirm()
        stateStore.update { state in
            state.confirmationRequired = false
            state.phase = .headlessActive
            state.phaseMessage = RuntimePhase.headlessActive.message
            state.phaseStartedAt = Date()
            state.phaseDeadlineAt = nil
            state.lastProgressAt = Date()
        }
        return true
    }

    public func rollbackIfNeeded() {
        if rollbackGuard.needsRollback() {
            logger.warn("Rollback deadline expired. Restoring Normal Mode.")
            setPhase(.rollbackExpired)
            restoreNormal()
        }
    }

    public func syncKeepAwakeWithState() {
        sleepManager.syncWithState()
    }

    public func syncVirtualDisplayState() {
        virtualDisplayManager.reconcileManagedVirtualDisplayIfNeeded()
    }

    public func refreshPhaseIfNeeded() {
        let state = stateStore.load()
        guard state.mode == .normal,
              state.phase == .coolingDown,
              RuntimePhaseFormatter.cooldownRemainingSeconds(state) == 0 else {
            return
        }

        stateStore.update { newState in
            newState.phase = .idle
            newState.phaseMessage = RuntimePhase.idle.message
            newState.phaseStartedAt = Date()
            newState.phaseDeadlineAt = nil
            newState.lastProgressAt = Date()
        }
        logger.info("[Phase] idle")
    }

    public func setKeepAwake(_ enabled: Bool) throws {
        if enabled {
            try sleepManager.enableKeepAwake()
        } else {
            sleepManager.disableKeepAwake()
        }
    }

    private func createSoftwareVirtualDisplay(resolution: Resolution, config: AppConfig) throws -> UInt32? {
        let timing = config.effectiveTiming
        setPhase(.creatingVirtualDisplay)
        setPhase(.waitingForVirtualDisplayEnumeration, timeoutSeconds: timing.virtualDisplayEnumerationWaitSeconds)
        return try virtualDisplayManager.createVirtualDisplay(
            resolution: resolution,
            refreshRate: config.virtualDisplay.refreshRate,
            scaleMode: config.virtualDisplay.scaleMode,
            waitTimeoutSeconds: TimeInterval(timing.virtualDisplayEnumerationWaitSeconds),
            reportedIDExtraWaitSeconds: TimeInterval(timing.virtualDisplayReportedIDExtraWaitSeconds)
        )
    }

    private func cleanFailedEnable(message: String) {
        virtualDisplayManager.destroyVirtualDisplayIfManaged()
        sleepManager.disableKeepAwake()
        let timing = configManager.load().effectiveTiming
        stateStore.update { cleanState in
            Self.resetRuntimeState(
                &cleanState,
                lastError: message,
                cooldownUntil: Date().addingTimeInterval(TimeInterval(timing.restoreCooldownAfterPausedSeconds))
            )
            cleanState.phase = .error
            cleanState.phaseMessage = RuntimePhase.error.message
            cleanState.phaseStartedAt = Date()
            cleanState.phaseDeadlineAt = nil
            cleanState.lastProgressAt = Date()
        }
        logger.error("[Enable] aborted; Normal Mode preserved.")
    }

    private func abortFailedHandoff(
        message: String,
        builtInDisplayID: UInt32?,
        softDisconnected: Bool
    ) {
        logger.warn("[Safety] restoring Normal Mode after display handoff failure.")

        if softDisconnected {
            let result = builtInDisplayManager.restoreBuiltInDisplay(displayID: builtInDisplayID)
            if result.success {
                logger.info(result.message)
                if let builtInDisplayID {
                    _ = displayManager.waitForDisplay(id: builtInDisplayID, present: true, timeoutSeconds: 5)
                }
            } else {
                logger.warn(result.message)
            }
        }
        if let builtInDisplayID,
           displayManager.display(id: builtInDisplayID) != nil {
            do {
                _ = try displayManager.setMainDisplay(id: builtInDisplayID, reason: "built-in display during failed handoff recovery")
            } catch {
                logger.warn("Failed to restore built-in display as main after handoff failure: \(error.localizedDescription)")
            }
        }

        _ = touchBarManager.showIfNeeded(stateStore.load().touchBarHidden)
        _ = builtInDisplayManager.restoreBrightness(stateStore.load().originalBrightness)
        cleanFailedEnable(message: message)
    }

    private func setPhase(_ phase: RuntimePhase, timeoutSeconds: Int? = nil) {
        let startedAt = Date()
        stateStore.update { state in
            state.phase = phase
            state.phaseMessage = phase.message
            state.phaseStartedAt = startedAt
            state.phaseDeadlineAt = timeoutSeconds.map { startedAt.addingTimeInterval(TimeInterval($0)) }
            state.lastProgressAt = startedAt
        }
        if let timeoutSeconds {
            logger.info("[Phase] \(phase.rawValue), timeout=\(timeoutSeconds)s")
        } else {
            logger.info("[Phase] \(phase.rawValue)")
        }
    }

    private static func resetRuntimeState(
        _ state: inout RuntimeState,
        lastError: String?,
        cooldownUntil: Date?
    ) {
        state.mode = .normal
        state.keepAwake = false
        state.caffeinatePID = nil
        state.rollbackDeadline = nil
        state.rollbackConfirmed = true
        state.lastError = lastError
        state.originalBrightness = nil
        state.activeResolutionOverride = nil
        state.virtualDisplayCreated = false
        state.virtualDisplayPID = nil
        state.virtualDisplayID = nil
        state.virtualDisplayRequestedResolution = nil
        state.virtualDisplayRefreshRate = nil
        state.virtualDisplayScaleMode = nil
        state.builtInBrightnessDimmed = false
        state.builtInBrightnessMethod = nil
        state.externalDisplayPromoted = false
        state.keepAwakeBackend = nil
        state.builtInSoftDisconnected = false
        state.builtInSoftDisconnectMethod = nil
        state.softDisconnectedDisplayID = nil
        state.builtInSoftDisconnectLastMessage = nil
        state.touchBarHidden = false
        state.touchBarHideMethod = nil
        state.touchBarLastMessage = nil
        state.restoreCooldownUntil = cooldownUntil
        state.builtInDisplayID = nil
        state.builtInWasMain = nil
        state.replacementDisplayID = nil
        state.replacementDisplayType = nil
        state.replacementDisplayReady = false
        state.replacementDisplayPromoted = false
        state.confirmationRequired = false
        state.enableCancellationRequested = false
    }

    private func isUsableHeadlessState(_ state: RuntimeState) -> Bool {
        let activeMode = state.mode == .headless || state.mode == .confirmRequired
        return activeMode
            && state.keepAwake
            && state.externalDisplayPromoted == true
            && (state.builtInBrightnessDimmed == true || state.builtInSoftDisconnected == true)
    }

    public func statusText() -> String {
        rollbackIfNeeded()
        syncVirtualDisplayState()
        refreshPhaseIfNeeded()

        let config = configManager.load()
        let state = stateStore.load()
        let virtualDisplayPolicy = VirtualDisplayPolicy.effectivePolicy(for: config.virtualDisplay)
        let confirmation = config.effectiveConfirmation
        let pidText = state.caffeinatePID.map(String.init) ?? "Not Running"
        let backendText = state.keepAwakeBackend ?? config.keepAwakeBackend?.rawValue ?? KeepAwakeBackend.caffeinate.rawValue
        let deadlineText = state.rollbackDeadline.map { ISO8601DateFormatter().string(from: $0) } ?? "None"
        let rollbackText = state.rollbackConfirmed ? "Confirmed" : "Pending until \(deadlineText)"
        let activeResolution = state.activeResolutionOverride ?? config.virtualDisplay.resolution
        let virtualDisplayRequestedResolution = state.virtualDisplayRequestedResolution ?? activeResolution
        let virtualDisplayRefreshRate = state.virtualDisplayRefreshRate ?? config.virtualDisplay.refreshRate
        let virtualDisplayScaleMode = state.virtualDisplayScaleMode ?? config.virtualDisplay.scaleMode
        let main = displayManager.displays().first { $0.isMain }
        let virtualDisplay = state.virtualDisplayID.flatMap { id in
            displayManager.displays().first { $0.id == id }
        }
        let virtualDisplayObservedResolution = virtualDisplay.map { "\($0.width)x\($0.height)" } ?? "Not Active"
        let virtualDisplayBackingScale = virtualDisplay.map {
            Self.virtualDisplayBackingScaleText(
                requested: virtualDisplayRequestedResolution,
                observedWidth: $0.width,
                observedHeight: $0.height
            )
        } ?? "Not Active"
        let mainText = main.map { display -> String in
            if display.id == state.virtualDisplayID {
                return "Managed Virtual"
            }
            return display.isBuiltIn ? "Built-in" : "External / Dummy"
        } ?? "Unknown"
        let brightnessText = builtInDisplayManager.currentBrightness().map { String(format: "%.2f", $0) } ?? "Unknown"
        let builtInHandling: String
        if state.builtInSoftDisconnected == true {
            builtInHandling = "Soft-disconnected\(state.builtInSoftDisconnectMethod.map { " via \($0)" } ?? "")"
        } else if state.builtInBrightnessDimmed == true {
            builtInHandling = "Dimmed\(state.builtInBrightnessMethod.map { " via \($0)" } ?? "")"
        } else if state.lastError?.contains("brightness control was unavailable") == true {
            builtInHandling = "Active (brightness control unavailable)"
        } else {
            builtInHandling = "Active / Not Dimmed"
        }
        let softDisconnectText = state.builtInSoftDisconnectLastMessage.map { "\nSoft Disconnect: \($0)" } ?? ""
        let touchBarText = state.touchBarLastMessage.map { "\nTouch Bar: \($0)" } ?? ""
        let lastErrorText = state.lastError.map { "\nLast Error: \($0)" } ?? ""
        let phaseElapsedText = RuntimePhaseFormatter.elapsedSeconds(state).map { "\($0)s" } ?? "Not Active"
        let phaseDeadlineText = RuntimePhaseFormatter.deadlineRemainingSeconds(state).map { "\($0)s" } ?? "Not Active"
        let cooldownRemaining = RuntimePhaseFormatter.cooldownRemainingSeconds(state)

        return """
        CodexHeadless Status
        --------------------
        Mode: \(state.mode.rawValue)
        Phase: \(RuntimePhaseFormatter.phase(state).rawValue)
        Phase Message: \(RuntimePhaseFormatter.message(state))
        Phase Elapsed: \(phaseElapsedText)
        Phase Deadline: \(phaseDeadlineText)
        Cooldown Remaining: \(cooldownRemaining)s
        Keep Awake: \(state.keepAwake ? "On" : "Off")
        Keep Awake Backend: \(backendText)
        Caffeinate PID: \(pidText)

        Displays:
        \(displayManager.statusLines(managedVirtualDisplayID: state.virtualDisplayID).joined(separator: "\n"))

        Virtual Display:
          Active: \(state.virtualDisplayCreated ? "Yes" : "No")
          Requested Resolution: \(state.virtualDisplayCreated ? "\(virtualDisplayRequestedResolution) @ \(virtualDisplayRefreshRate)Hz" : "Not Active")
          Requested Scale Mode: \(state.virtualDisplayCreated ? virtualDisplayScaleMode : "Not Active")
          Observed Resolution: \(virtualDisplayObservedResolution)
          Backing Scale: \(virtualDisplayBackingScale)
          Display ID: \(state.virtualDisplayID.map(String.init) ?? "Not Active")
          Host PID: \(state.virtualDisplayPID.map(String.init) ?? "Not Running")

        Configured Virtual Display:
          Policy: \(virtualDisplayPolicy.rawValue)
          Resolution: \(config.virtualDisplay.resolution)
          Refresh Rate: \(config.virtualDisplay.refreshRate)Hz
          Scale Mode: \(config.virtualDisplay.scaleMode)

        Display Handoff:
          Built-in ID: \(state.builtInDisplayID.map(String.init) ?? "Not Active")
          Built-in Was Main: \(state.builtInWasMain.map { $0 ? "Yes" : "No" } ?? "Unknown")
          Replacement Type: \(state.replacementDisplayType ?? "Not Active")
          Replacement ID: \(state.replacementDisplayID.map(String.init) ?? "Not Active")
          Replacement Ready: \(state.replacementDisplayReady == true ? "Yes" : "No")
          Replacement Promoted: \(state.replacementDisplayPromoted == true ? "Yes" : "No")

        Confirmation:
          Policy: \(confirmation.policy.rawValue)
          Required: \(state.confirmationRequired == true ? "Yes" : "No")
          Timeout: \(confirmation.timeoutSeconds)s
          Dialog: \(confirmation.dialogEnabled ? "On" : "Off")

        Main Display: \(mainText)
        Built-in Brightness: \(brightnessText)
        Built-in Handling: \(builtInHandling)
        Touch Bar: \(state.touchBarHidden == true ? "UI hidden\(state.touchBarHideMethod.map { " via \($0)" } ?? "")" : "Active / Not Hidden")
        Rollback Guard: \(rollbackText)
        Log: \(CodexHeadlessPaths.logFile.path)
        Config: \(CodexHeadlessPaths.configFile.path)\(softDisconnectText)\(touchBarText)\(lastErrorText)
        """
    }

    private static func virtualDisplayBackingScaleText(
        requested: Resolution,
        observedWidth: Int,
        observedHeight: Int
    ) -> String {
        guard observedWidth > 0, observedHeight > 0 else {
            return "Unknown"
        }

        let widthScale = Double(requested.width) / Double(observedWidth)
        let heightScale = Double(requested.height) / Double(observedHeight)
        if abs(widthScale - heightScale) < 0.01 {
            return String(format: "%.2fx requested/observed", widthScale)
        }

        return String(format: "%.2fx width, %.2fx height requested/observed", widthScale, heightScale)
    }
}
