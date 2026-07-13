import Foundation

enum EnableCompensationDisposition {
    case notStarted
    case inProgressOrPaused
    case completed
}

struct EnableExecutionContext {
    var journalCreated = false
    var keepAwakeStarted = false
    var virtualDisplayCreated = false
    var replacementPromoted = false
    var builtInSoftDisconnected = false
    var brightnessDimmed = false
    var touchBarHidden = false
    var committed = false
    var builtInDisplayID: UInt32?
    var originalBrightness: Float?
    var compensationDisposition: EnableCompensationDisposition = .notStarted

    var hasSideEffects: Bool {
        journalCreated || keepAwakeStarted || virtualDisplayCreated || replacementPromoted
            || builtInSoftDisconnected || brightnessDimmed || touchBarHidden
    }
}

extension HeadlessController {
    func compensateEnableFailure(_ execution: EnableExecutionContext, cause: Error) throws {
        guard execution.hasSideEffects else { return }
        if let state = try? stateStore.read() {
            if state.mode == .restoring && state.phase == .restorePaused { return }
        }
        if execution.touchBarHidden {
            let touchBarRestore = touchBarManager.showIfNeeded(true)
            guard touchBarRestore.success else {
                try enterPausedRecoveryKeepingReplacementAlive(
                    reason: "Enable compensation could not restore the Touch Bar: \(touchBarRestore.message)"
                )
                return
            }
        }
        if execution.brightnessDimmed {
            guard let originalBrightness = execution.originalBrightness else {
                try enterPausedRecoveryKeepingReplacementAlive(
                    reason: "Brightness was changed but its original value is unavailable. Replacement display and Keep Awake were preserved."
                )
                return
            }
            let brightnessRestore = builtInDisplayManager.restoreBrightness(originalBrightness)
            guard brightnessRestore.success else {
                try enterPausedRecoveryKeepingReplacementAlive(
                    reason: "Built-in display brightness could not be restored. Replacement display and Keep Awake were preserved."
                )
                return
            }
        }
        let message = "Enable failed after a system side effect: \(cause.localizedDescription)"
        if execution.replacementPromoted || execution.builtInSoftDisconnected {
            try recoverFailedHandoff(
                message: message,
                builtInDisplayID: execution.builtInDisplayID,
                softDisconnected: execution.builtInSoftDisconnected
            )
        } else {
            try cleanupPreparedResourcesWhenBuiltInNeverDisconnected(message: message)
        }
    }

    func createSoftwareVirtualDisplay(resolution: Resolution, config: AppConfig) throws -> UInt32? {
        let timing = config.effectiveTiming
        try setPhase(.creatingVirtualDisplay)
        try setPhase(.waitingForVirtualDisplayEnumeration, timeoutSeconds: timing.virtualDisplayEnumerationWaitSeconds)
        return try virtualDisplayManager.createVirtualDisplay(
            resolution: resolution,
            refreshRate: config.virtualDisplay.refreshRate,
            scaleMode: config.virtualDisplay.scaleMode,
            waitTimeoutSeconds: TimeInterval(timing.virtualDisplayEnumerationWaitSeconds),
            reportedIDExtraWaitSeconds: TimeInterval(timing.virtualDisplayReportedIDExtraWaitSeconds)
        )
    }

    func cleanupPreparedResourcesWhenBuiltInNeverDisconnected(message: String) throws {
        let virtualCleanup = virtualDisplayManager.destroyVirtualDisplayIfManaged()
        guard virtualCleanup.completed else {
            try enterCleanupRecovery(reason: "Prepared virtual display cleanup \(virtualCleanup.summary).")
            throw CodexHeadlessError.managedResource(message: virtualCleanup.summary)
        }
        let keepAwakeCleanup = sleepManager.disableKeepAwake()
        guard keepAwakeCleanup.completed else {
            try enterCleanupRecovery(reason: "Prepared Keep Awake cleanup \(keepAwakeCleanup.summary).")
            throw CodexHeadlessError.managedResource(message: keepAwakeCleanup.summary)
        }
        let snapshot = processSnapshotProvider.capture()
        let keepAwakeObservation = sleepManager.managedResourceObservation(snapshot: snapshot)
        let virtualObservation = virtualDisplayManager.managedResourceObservation(snapshot: snapshot)
        guard keepAwakeObservation.status == .none,
              virtualObservation.status == .none,
              !displayManager.displays().contains(where: { $0.isManagedVirtual }) else {
            let reason = "Prepared resource cleanup could not be independently verified."
            try enterCleanupRecovery(reason: reason)
            throw CodexHeadlessError.managedResource(message: reason)
        }
        let timing = restoreTiming()
        try stateStore.transaction { cleanState in
            Self.resetRuntimeState(
                &cleanState,
                lastError: nil,
                cooldownUntil: clock.now.addingTimeInterval(TimeInterval(timing.restoreCooldownAfterPausedSeconds))
            )
            cleanState.lastOutcome = .recoveredWithWarning
            cleanState.lastWarning = message
            cleanState.phase = .coolingDown
            cleanState.phaseMessage = RuntimePhase.coolingDown.message
            cleanState.phaseStartedAt = clock.now
            cleanState.phaseDeadlineAt = nil
            cleanState.lastProgressAt = clock.now
        }
        do {
            try recoveryJournalStore.delete()
        } catch {
            try stateStore.transaction { state in
                state.mode = .error
                state.phase = .error
                state.phaseMessage = "Recovery Journal finalization is incomplete."
                state.lastError = "Prepared resources stopped, but Recovery Journal finalization failed: \(error.localizedDescription)"
            }
            throw error
        }
        logger.error("[Enable] aborted; Normal Mode preserved.")
    }

    func recoverFailedHandoff(
        message: String,
        builtInDisplayID: UInt32?,
        softDisconnected: Bool
    ) throws {
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
        if let builtInDisplayID, displayManager.display(id: builtInDisplayID) != nil {
            do {
                _ = try displayManager.setMainDisplay(id: builtInDisplayID, reason: "built-in display during failed handoff recovery")
            } catch {
                logger.warn("Failed to restore built-in display as main after handoff failure: \(error.localizedDescription)")
            }
        }

        let runtime = try stateStore.read()
        let physical = displayManager.displays().first {
            $0.isMain && !$0.isManagedVirtual && $0.id != runtime.virtualDisplayID
        } ?? displayManager.restorePriorityDisplay(managedVirtualDisplayID: runtime.virtualDisplayID)
        let verification = physical.map {
            displayManager.verifyPhysicalTakeover(
                displayID: $0.id,
                managedVirtualDisplayID: runtime.virtualDisplayID,
                stabilizationSeconds: 0.5
            )
        }
        let recoveryResult: FailedHandoffRecoveryResult
        if let physical, verification?.safeToDestroyVirtualDisplay == true {
            recoveryResult = .physicalDisplayRecovered(displayID: physical.id)
        } else {
            recoveryResult = .replacementMustRemainActive(
                reason: verification?.summary ?? "No physical display is available."
            )
        }
        guard case .physicalDisplayRecovered = recoveryResult else {
            let reason: String
            if case .replacementMustRemainActive(let detail) = recoveryResult {
                reason = detail
            } else {
                reason = "Physical recovery was not verified."
            }
            try enterPausedRecoveryKeepingReplacementAlive(reason: "Failed handoff recovery must keep the replacement display active. \(reason)")
            return
        }

        _ = touchBarManager.showIfNeeded(runtime.touchBarHidden)
        if runtime.builtInBrightnessDimmed == true {
            guard let originalBrightness = runtime.originalBrightness else {
                try enterPausedRecoveryKeepingReplacementAlive(
                    reason: "Built-in brightness restore is required, but the original value is unavailable."
                )
                return
            }
            let brightnessRestore = builtInDisplayManager.restoreBrightness(originalBrightness)
            guard brightnessRestore.success else {
                try enterPausedRecoveryKeepingReplacementAlive(
                    reason: "Built-in brightness restore failed. Replacement display and Keep Awake were preserved."
                )
                return
            }
        }
        try cleanupAfterVerifiedPhysicalRecovery(message: message)
    }

    func cleanupAfterVerifiedPhysicalRecovery(message: String) throws {
        try cleanupPreparedResourcesWhenBuiltInNeverDisconnected(message: message)
    }

    func enterPausedRecoveryKeepingReplacementAlive(reason: String) throws {
        logger.error("[Safety] \(reason) Managed virtual display and Keep Awake remain active.")
        try stateStore.transaction { state in
            state.mode = .restoring
            state.phase = .restorePaused
            state.phaseMessage = RuntimePhase.restorePaused.message
            state.phaseStartedAt = clock.now
            state.phaseDeadlineAt = nil
            state.lastProgressAt = clock.now
            state.lastError = reason
            state.lastOutcome = .pausedForSafety
            state.rollbackDeadline = nil
            state.rollbackConfirmed = true
        }
        try? recoveryJournalStore.update { $0.stage = .recoveryRequired }
    }

    func setPhase(_ phase: RuntimePhase, timeoutSeconds: Int? = nil) throws {
        let startedAt = clock.now
        try stateStore.transaction { state in
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

    func restoreTiming() -> TimingConfig {
        do {
            let config = try configManager.read()
            guard configManager.health().isHealthy else {
                logger.warn("Restore timing is using safe defaults because config health is degraded.")
                return .safeRestoreDefault
            }
            return config.effectiveTiming
        } catch {
            logger.warn("Restore timing is using safe defaults because config is unavailable: \(error.localizedDescription)")
            return .safeRestoreDefault
        }
    }

    static func resetRuntimeState(
        _ state: inout RuntimeState,
        lastError: String?,
        cooldownUntil: Date?
    ) {
        state.mode = .normal
        state.keepAwake = false
        state.caffeinatePID = nil
        state.keepAwakeHost = nil
        state.rollbackDeadline = nil
        state.rollbackConfirmed = true
        state.lastError = lastError
        state.lastWarning = nil
        state.lastOutcome = lastError == nil ? .success : .failed
        state.originalBrightness = nil
        state.activeResolutionOverride = nil
        state.virtualDisplayCreated = false
        state.virtualDisplayPID = nil
        state.virtualDisplayID = nil
        state.virtualDisplayRequestedResolution = nil
        state.virtualDisplayRefreshRate = nil
        state.virtualDisplayScaleMode = nil
        state.virtualDisplayHost = nil
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

    func isUsableHeadlessState(_ state: RuntimeState) -> Bool {
        let activeMode = state.mode == .headless || state.mode == .confirmRequired
        return activeMode
            && state.keepAwake
            && state.externalDisplayPromoted == true
            && (state.builtInBrightnessDimmed == true || state.builtInSoftDisconnected == true)
    }

}
