import Foundation

extension HeadlessController {
    public func enableHeadless(resolutionOverride: Resolution? = nil, rollbackEnabled: Bool = true) throws {
        logger.info("[Enable] requested.")
        let enableStarted = clock.uptime
        defer { logger.info("[Perf] enable coreMs=\(Int((clock.uptime - enableStarted) * 1000))") }
        let operation = try operationLock.acquire(name: "enable")
        defer { operation.release() }
        var execution = EnableExecutionContext()
        do {

        let config = try configManager.read()
        guard configManager.health().isHealthy else {
            throw CodexHeadlessError.configurationRecoveryRequired
        }

        var state = try stateStore.read()
        let assessmentStarted = clock.uptime
        try CleanNormalAssessor(
            stateStore: stateStore,
            recoveryJournalStore: recoveryJournalStore,
            sleepManager: sleepManager,
            virtualDisplayManager: virtualDisplayManager,
            displayManager: displayManager,
            snapshotProvider: processSnapshotProvider
        ).requireCleanNormal(for: "enable Headless Mode")
        logger.info("[Perf] clean-normal durationMs=\(Int((clock.uptime - assessmentStarted) * 1000)) processSnapshots=1 context=enable")
        if let cooldownUntil = state.restoreCooldownUntil,
           cooldownUntil > clock.now {
            let remaining = Int(ceil(cooldownUntil.timeIntervalSince(clock.now)))
            throw CodexHeadlessError.restoreCooldown(secondsRemaining: remaining)
        }

        let displays = displayManager.displays()
        let builtInDisplay = displays.first { $0.isBuiltIn }
        let builtInDisplayID = builtInDisplay?.id
        let brightnessCapability = builtInDisplayManager.brightnessCapability()
        let brightnessFallbackMayBeRequired = builtInDisplay != nil
            && (config.softDisconnectBuiltInDisplay != true
                || config.effectiveDisplayHandoff.onSoftDisconnectFailure == .brightnessFallback)
        let originalBrightness = brightnessFallbackMayBeRequired
            ? builtInDisplayManager.currentBrightness()
            : nil
        if brightnessFallbackMayBeRequired,
           (!brightnessCapability.available || originalBrightness == nil) {
            throw CodexHeadlessError.brightnessCapabilityUnavailable(
                message: "Brightness fallback is unavailable because the original built-in display brightness cannot be read and restored reliably. Enable soft-disconnect with restore-on-failure, or connect a physical display."
            )
        }

        setInProcessEnableCancellation(false)
        _ = try recoveryJournalStore.create(operationID: operation.operationID)
        execution.journalCreated = true
        try recoveryJournalStore.update { journal in
            journal.builtInDisplayID = builtInDisplayID
            journal.builtInWasMain = builtInDisplay?.isMain
        }
        state.mode = .preparing
        state.lastError = nil
        state.lastWarning = nil
        state.restoreCooldownUntil = nil
        state.activeResolutionOverride = resolutionOverride
        state.originalBrightness = originalBrightness
        execution.originalBrightness = originalBrightness
        state.phase = .startingKeepAwake
        state.phaseMessage = RuntimePhase.startingKeepAwake.message
        state.phaseStartedAt = clock.now
        state.phaseDeadlineAt = nil
        state.lastProgressAt = clock.now
        state.builtInDisplayID = nil
        state.builtInWasMain = nil
        state.replacementDisplayID = nil
        state.replacementDisplayType = nil
        state.replacementDisplayReady = false
        state.replacementDisplayPromoted = false
        state.confirmationRequired = false
        state.enableCancellationRequested = false
        try stateStore.save(state)
        try failureInjector.check(.initialPreparingState)

        let timing = config.effectiveTiming
        let resolution = resolutionOverride ?? config.virtualDisplay.resolution
        let virtualDisplayPolicy = VirtualDisplayPolicy.effectivePolicy(for: config.virtualDisplay)
        try virtualDisplayManager.validateResolution(resolution)
        logger.info("Requested virtual display resolution: \(resolution) @ \(config.virtualDisplay.refreshRate)Hz, policy=\(virtualDisplayPolicy.rawValue).")

        try setPhase(.startingKeepAwake)
        try sleepManager.enableKeepAwake()
        execution.keepAwakeStarted = true
        try failureInjector.check(.keepAwakeStarted)

        try setPhase(.checkingDisplays)
        logger.info("Displays before headless: \(displays.map { "\($0.id):\($0.typeLabel):\($0.width)x\($0.height):main=\($0.isMain)" }.joined(separator: ", "))")
        displayLayoutStore.saveCurrentLayout(
            displayManager: displayManager,
            reason: "before entering Headless Mode"
        )

        execution.builtInDisplayID = builtInDisplayID
        let existingExternalDisplayID = displayManager.preferredExternalDisplay()?.id
        let hasExternal = displayManager.hasAlternativeDisplay()
        try stateStore.transaction { runtime in
            runtime.builtInDisplayID = builtInDisplayID
            runtime.builtInWasMain = builtInDisplay?.isMain
        }
        try recoveryJournalStore.update { journal in
            journal.builtInDisplayID = builtInDisplayID
            journal.builtInWasMain = builtInDisplay?.isMain
        }

        // Prepare: create and validate a replacement while the built-in display stays available.
        var virtualDisplayID: UInt32?
        let shouldCreateVirtualDisplay = virtualDisplayPolicy == .always || (virtualDisplayPolicy == .auto && !hasExternal)
        if shouldCreateVirtualDisplay {
            do {
                virtualDisplayID = try createSoftwareVirtualDisplay(resolution: resolution, config: config)
                execution.virtualDisplayCreated = virtualDisplayID != nil
                try failureInjector.check(.virtualHostCreated)
                try failureInjector.check(.virtualDisplayConfirmed)
            } catch {
                let message = "Unable to create a usable virtual display. Normal Mode has been preserved."
                logger.error("[VirtualDisplay] failed to create a usable replacement display: \(error.localizedDescription)")
                throw CodexHeadlessError.virtualDisplayUnavailable(message: "\(message) Cause: \(error.localizedDescription)")
            }
            if virtualDisplayID != nil {
                try setPhase(.validatingVirtualDisplay)
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
                throw CodexHeadlessError.displayHandoffFailed(message: message)
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
            try setPhase(.preparingExternalDisplay)
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
            throw CodexHeadlessError.virtualDisplayUnavailable(message: message)
        }

        try setPhase(.replacementDisplayReady)
        try stateStore.transaction { runtime in
            runtime.replacementDisplayID = replacementDisplayID
            runtime.replacementDisplayType = replacementType
            runtime.replacementDisplayReady = true
        }
        try recoveryJournalStore.update { journal in
            journal.replacementDisplayID = replacementDisplayID
            journal.replacementDisplayType = replacementType
            journal.stage = .replacementReady
        }
        try failureInjector.check(.replacementReady)

        if isEnableCancellationRequested() {
            let message = "Enable was cancelled by a Restore request. Normal Mode has been preserved."
            logger.info("[Enable] cancelled before display handoff commit.")
            throw CodexHeadlessError.enableCancelled(message: message)
        }

        // Commit: promotion and soft-disconnect intentionally run back-to-back.
        try setPhase(.committingDisplayHandoff)
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
            let message = "Unable to set the replacement display as main. Headless Mode was not started; safe recovery was requested."
            execution.compensationDisposition = .inProgressOrPaused
            try recoverFailedHandoff(message: message, builtInDisplayID: builtInDisplayID, softDisconnected: false)
            execution.compensationDisposition = .completed
            throw CodexHeadlessError.displayHandoffFailed(message: message)
        }
        guard promotedExternal else {
            let message = "Unable to set the replacement display as main. Headless Mode was not started; safe recovery was requested."
            execution.compensationDisposition = .inProgressOrPaused
            try recoverFailedHandoff(message: message, builtInDisplayID: builtInDisplayID, softDisconnected: false)
            execution.compensationDisposition = .completed
            throw CodexHeadlessError.displayHandoffFailed(message: message)
        }
        execution.replacementPromoted = true
        try stateStore.transaction { $0.replacementDisplayPromoted = true }
        try recoveryJournalStore.update { $0.stage = .handoffCommitted }
        try failureInjector.check(.replacementPromoted)

        try setPhase(.disconnectingBuiltInDisplay)
        logger.info("[Display] soft-disconnecting built-in display \(builtInDisplayID.map(String.init) ?? "unknown").")
        let softDisconnectResult = builtInDisplayManager.attemptSoftDisconnectIfSafe(
            builtInDisplayID: builtInDisplayID,
            hasAlternativeDisplay: hasExternal || promotedExternal,
            enabled: config.softDisconnectBuiltInDisplay == true
        )
        let softDisconnected = softDisconnectResult.success
        execution.builtInSoftDisconnected = softDisconnected
        if softDisconnected {
            logger.info(softDisconnectResult.message)
            do {
                try recoveryJournalStore.update { journal in
                    journal.builtInSoftDisconnected = true
                    journal.softDisconnectMethod = softDisconnectResult.method
                    journal.stage = .builtInSoftDisconnected
                }
                try stateStore.transaction { state in
                    state.builtInSoftDisconnected = true
                    state.builtInSoftDisconnectMethod = softDisconnectResult.method
                    state.softDisconnectedDisplayID = builtInDisplayID
                    state.builtInSoftDisconnectLastMessage = softDisconnectResult.message
                }
                try failureInjector.check(.softDisconnectSucceeded)
            } catch {
                logger.error("[Safety] soft-disconnect succeeded but state persistence failed: \(error.localizedDescription)")
                execution.compensationDisposition = .inProgressOrPaused
                try recoverFailedHandoff(
                    message: "Soft-disconnect state could not be persisted; safe recovery was requested.",
                    builtInDisplayID: builtInDisplayID,
                    softDisconnected: true
                )
                execution.compensationDisposition = .completed
                throw error
            }
            try setPhase(.waitingForBuiltInDisplayDisconnect, timeoutSeconds: timing.softDisconnectDisappearWaitSeconds)
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

            if config.effectiveDisplayHandoff.onSoftDisconnectFailure == .restore || !brightnessCapability.available {
                let message = "The built-in display could not be disconnected. Headless Mode was not started; safe recovery was requested."
                execution.compensationDisposition = .inProgressOrPaused
                try recoverFailedHandoff(message: message, builtInDisplayID: builtInDisplayID, softDisconnected: false)
                execution.compensationDisposition = .completed
                throw CodexHeadlessError.displayHandoffFailed(message: message)
            }
        }

        var brightnessDimmed = false
        var brightnessMethod: String?
        if !softDisconnected {
            let brightnessResult = builtInDisplayManager.dimBuiltInDisplay()
            brightnessDimmed = brightnessResult.success
            execution.brightnessDimmed = brightnessResult.success
            brightnessMethod = brightnessResult.success ? brightnessResult.method : nil
            if brightnessResult.success {
                logger.info(brightnessResult.message)
                try failureInjector.check(.brightnessDimmed)
            } else {
                logger.warn(brightnessResult.message)
            }
        }

        try setPhase(.verifyingDisplayHandoff)
        let verificationState = try stateStore.read()
        let managedHostStillRecorded = usedManagedVirtualDisplay
            && verificationState.virtualDisplayPID != nil
        let replacementStillUsable = displayManager.displays().contains {
            $0.id == replacementDisplayID && $0.isActive && ($0.isOnline || $0.isManagedVirtual)
        }
            || managedHostStillRecorded
        if !replacementStillUsable {
            let message = "The replacement display became unavailable during handoff. Safe recovery was requested."
            execution.compensationDisposition = .inProgressOrPaused
            try recoverFailedHandoff(message: message, builtInDisplayID: builtInDisplayID, softDisconnected: softDisconnected)
            execution.compensationDisposition = .completed
            throw CodexHeadlessError.displayHandoffFailed(message: message)
        }

        let headlessReady = promotedExternal && (softDisconnected || brightnessDimmed)
        if !headlessReady {
            let message = "The built-in display could not be safely handed off. Safe recovery was requested."
            execution.compensationDisposition = .inProgressOrPaused
            try recoverFailedHandoff(message: message, builtInDisplayID: builtInDisplayID, softDisconnected: softDisconnected)
            execution.compensationDisposition = .completed
            throw CodexHeadlessError.displayHandoffFailed(message: message)
        }
        try setPhase(.hidingTouchBar)
        let touchBarResult = touchBarManager.hideIfEnabled(config.hideTouchBarInHeadless == true)
        execution.touchBarHidden = touchBarResult.success
        if touchBarResult.success {
            logger.info(touchBarResult.message)
            try failureInjector.check(.touchBarHidden)
        } else if config.hideTouchBarInHeadless == true {
            logger.warn(touchBarResult.message)
        }
        try recoveryJournalStore.update { $0.touchBarHidden = touchBarResult.success }

        sleepManager.applyDisplaySleepFast()

        let confirmation = config.effectiveConfirmation
        let confirmationRequired = rollbackEnabled
            && confirmation.policy.requiresConfirmation(usedManagedVirtualDisplay: usedManagedVirtualDisplay)
        try failureInjector.check(.finalHeadlessCommit)
        let finalMode = try stateStore.transaction { state -> HeadlessMode in
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
            state.confirmationRequired = confirmationRequired
            state.lastOutcome = .success
            state.mode = confirmationRequired ? .confirmRequired : .headless
            state.phase = confirmationRequired ? .waitingForConfirmation : .headlessActive
            state.phaseMessage = state.phase?.message
            state.phaseStartedAt = clock.now
            state.phaseDeadlineAt = confirmationRequired
                ? clock.now.addingTimeInterval(TimeInterval(confirmation.timeoutSeconds))
                : nil
            state.lastProgressAt = clock.now
            state.rollbackConfirmed = !confirmationRequired
            state.rollbackDeadline = state.phaseDeadlineAt
            return state.mode
        }
        try recoveryJournalStore.update { $0.stage = .headless }
        execution.committed = true

        logger.info("[Display] handoff completed.")
        logger.info("[Confirmation] policy=\(confirmation.policy.rawValue), required=\(confirmationRequired).")
        logger.info("Headless Mode entered with mode \(finalMode.rawValue). External promoted: \(promotedExternal).")
        } catch {
            if !execution.committed && execution.compensationDisposition == .notStarted {
                do {
                    execution.compensationDisposition = .inProgressOrPaused
                    try compensateEnableFailure(execution, cause: error)
                    execution.compensationDisposition = .completed
                } catch let compensationError {
                    logger.error("[Enable] compensation stopped safely: \(compensationError.localizedDescription)")
                }
            }
            throw error
        }
    }

}
