import Foundation

extension HeadlessController {
    @discardableResult
    public func restoreNormal() -> RestoreResult {
        logger.info("Restore Normal Mode requested.")
        let restoreStarted = clock.uptime
        defer { logger.info("[Perf] restore coreMs=\(Int((clock.uptime - restoreStarted) * 1000))") }
        let operation: WorkflowOperationLeaseHandling
        do {
            operation = try operationLock.acquire(name: "restore")
        } catch {
            logger.error("Restore could not acquire the workflow lock: \(error.localizedDescription)")
            return .failed(reason: error.localizedDescription)
        }
        defer { operation.release() }
        do {
            return try restoreNormalLocked(markRollbackExpired: false)
        } catch {
            logger.error("[Safety] Restore stopped because critical recovery data could not be persisted: \(error.localizedDescription). No Normal success was recorded; inspect state and Recovery Journal for exact cleanup progress.")
            return .failed(reason: error.localizedDescription)
        }
    }

    func restoreNormalLocked(markRollbackExpired: Bool) throws -> RestoreResult {
        let state: RuntimeState
        do {
            state = try stateStore.read()
        } catch StateStoreError.corruptedState(_, let underlying) {
            return try safeRestoreLocked(reason: underlying.localizedDescription)
        }
        do {
            try ensureRecoveryJournalForRestore(state: state)
        } catch RecoveryJournalStoreError.unsupportedSchema(let version) {
            let reason = "Recovery Journal schema v\(version) requires a newer CodexHeadless build. The journal and managed resources were preserved. Upgrade the application before restoring."
            logger.error("[Recovery] \(reason)")
            return .recoveryRequired(reason: reason)
        } catch RecoveryJournalStoreError.damaged(_, let underlying) {
            let reason = "Recovery Journal is damaged and cannot be rebuilt without independently verified resource ownership: \(underlying.localizedDescription). Managed resources were preserved."
            logger.error("[Recovery] \(reason)")
            return .recoveryRequired(reason: reason)
        } catch CodexHeadlessError.recoveryJournalUnavailable(let message) {
            logger.error("[Recovery] \(message)")
            return .recoveryRequired(reason: message)
        }
        if markRollbackExpired {
            try setPhase(.rollbackExpired)
        }
        let journalForRestore = try recoveryJournalStore.read()
        let journalPresent = journalForRestore != nil
        let allowedFinalizingOperationID = state.mode == .normal && journalForRestore?.cleanupProgress.finalStatePersisted == true
            ? journalForRestore?.operationID
            : nil
        let cleanAssessment = CleanNormalAssessor(
            stateStore: stateStore,
            recoveryJournalStore: recoveryJournalStore,
            sleepManager: sleepManager,
            virtualDisplayManager: virtualDisplayManager,
            displayManager: displayManager,
            snapshotProvider: processSnapshotProvider
        ).assess(allowingFinalizingJournalOperationID: allowedFinalizingOperationID)
        let observedManagedResources = cleanAssessment.keepAwakeObservation.status != .none
            || cleanAssessment.virtualDisplayObservation.status != .none
            || displayManager.displays().contains(where: { $0.isManagedVirtual })
        if state.mode == .normal,
           !observedManagedResources,
           let journal = try recoveryJournalStore.read(),
           journal.cleanupProgress.finalStatePersisted {
            return evaluateRestoreSuccess(
                result: .alreadyNormal,
                finalizingJournalOperationID: journal.operationID,
                precomputedAssessment: cleanAssessment
            )
        }
        if state.mode == .normal,
           state.keepAwake == false,
           state.virtualDisplayCreated == false,
           (observedManagedResources || journalPresent) {
            return try safeRestoreLocked(reason: "Runtime state is missing managed resources observed on the system.")
        }
        if state.mode == .normal,
           state.keepAwake == false,
           state.virtualDisplayCreated == false,
           state.builtInSoftDisconnected != true,
           state.builtInBrightnessDimmed != true,
           state.touchBarHidden != true,
           !journalPresent,
           cleanAssessment.isClean {
            try stateStore.transaction { newState in
                newState.phase = .idle
                newState.phaseMessage = RuntimePhase.idle.message
                newState.phaseStartedAt = clock.now
                newState.phaseDeadlineAt = nil
                newState.lastProgressAt = clock.now
            }
            logger.info("Normal Mode is already restored.")
            return evaluateRestoreSuccess(
                result: .alreadyNormal,
                finalizingJournalOperationID: nil,
                precomputedAssessment: cleanAssessment
            )
        }
        if state.mode == .normal,
           !journalPresent,
           !cleanAssessment.isClean {
            return .recoveryRequired(
                reason: "Runtime says Normal but Clean Normal is violated: \(cleanAssessment.violations.joined(separator: " "))"
            )
        }

        let timing = restoreTiming()
        let restoringAfterPaused = state.phase == .restorePaused || state.mode == .error
        try stateStore.transaction { newState in
            newState.mode = .restoring
        }
        try rollbackGuard.cancel()
        try recoveryJournalStore.update { $0.stage = .restoringPhysicalDisplay }
        try setPhase(.restoringBuiltInDisplay)

        if state.builtInSoftDisconnected == true {
            let restoreDisplayResult = builtInDisplayManager.restoreBuiltInDisplay(displayID: state.softDisconnectedDisplayID)
            if restoreDisplayResult.success {
                logger.info(restoreDisplayResult.message)
                try setPhase(.waitingForPhysicalDisplay, timeoutSeconds: timing.restoreBuiltInShortWaitSeconds)
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

        try setPhase(.waitingForPhysicalDisplay, timeoutSeconds: timing.restorePhysicalDisplayWaitSeconds)
        logger.info("[Phase] waitingForPhysicalDisplay, shortWait=\(timing.restoreBuiltInShortWaitSeconds)s, maxWait=\(timing.restorePhysicalDisplayWaitSeconds)s")
        var restoreDisplay = displayManager.waitForRestorePriorityDisplay(
            managedVirtualDisplayID: state.virtualDisplayID,
            timeoutSeconds: TimeInterval(timing.restorePhysicalDisplayWaitSeconds)
        )
        if restoreDisplay == nil {
            logger.warn("Physical display was not enumerated before primary timeout; entering final grace polling.")
            restoreDisplay = try waitForRestorePriorityDisplayDuringGrace(
                managedVirtualDisplayID: state.virtualDisplayID,
                timing: timing
            )
        }

        guard restoreDisplay != nil else {
            logger.warn("Physical display still unavailable after grace polling; entering paused restore and keeping managed virtual display alive for safety.")
            try stateStore.transaction { newState in
                newState.mode = .restoring
                newState.phase = .restorePaused
                newState.phaseMessage = RuntimePhase.restorePaused.message
                newState.phaseStartedAt = clock.now
                newState.phaseDeadlineAt = nil
                newState.lastProgressAt = clock.now
                newState.lastError = "Restore paused while waiting for a physical display."
                newState.lastOutcome = .pausedForSafety
                newState.rollbackDeadline = nil
                newState.rollbackConfirmed = true
            }
            return .pausedForSafety(reason: "Restore paused while waiting for a physical display.")
        }

        if let restoreDisplay {
            logger.info("Physical display became available: displayID=\(restoreDisplay.id)")
        }
        return try finishRestoreAfterPhysicalDisplayAvailable(state: state, afterPausedRestore: restoringAfterPaused)
    }

    public func continuePausedRestoreIfReady() {
        let operation: WorkflowOperationLeaseHandling
        do {
            operation = try operationLock.acquire(name: "resume-paused-restore", timeoutSeconds: 0.1, logLifecycle: false)
        } catch {
            return
        }
        defer { operation.release() }

        do {
            let state = try stateStore.read()
            guard state.mode == .restoring,
                  state.phase == .restorePaused,
                  displayManager.restorePriorityDisplay(managedVirtualDisplayID: state.virtualDisplayID) != nil else {
                return
            }
            logger.info("Paused restore resumed after a physical display became available.")
            _ = try finishRestoreAfterPhysicalDisplayAvailable(state: state, afterPausedRestore: true)
        } catch {
            logger.error("Paused restore resume stopped safely: \(error.localizedDescription)")
        }
    }

    func finishRestoreAfterPhysicalDisplayAvailable(state: RuntimeState, afterPausedRestore: Bool) throws -> RestoreResult {
        let timing = restoreTiming()
        try setPhase(.promotingPhysicalDisplay)
        var promotedDisplayID: UInt32?
        do {
            if let restoreDisplay = displayManager.restorePriorityDisplay(managedVirtualDisplayID: state.virtualDisplayID),
               restoreDisplay.isMain {
                try setPhase(.keepingExternalDisplayAsMain)
                logger.info("Keeping physical display as main display: \(restoreDisplay.id)")
                promotedDisplayID = restoreDisplay.id
            } else {
                try displayManager.setMainDisplayToRestorePriority(managedVirtualDisplayID: state.virtualDisplayID)
                promotedDisplayID = displayManager.restorePriorityDisplay(managedVirtualDisplayID: state.virtualDisplayID)?.id
            }
            restoreSavedDisplayLayout(managedVirtualDisplayID: state.virtualDisplayID)
            promotedDisplayID = displayManager.displays().first {
                $0.isMain && !$0.isManagedVirtual && $0.id != state.virtualDisplayID
            }?.id ?? promotedDisplayID
        } catch {
            logger.warn("Failed to restore preferred main display before virtual display cleanup: \(error.localizedDescription)")
        }

        let stabilizationSeconds = Double(timing.effectiveRestorePostPromoteStabilizationMilliseconds) / 1000.0
        guard let takeoverDisplayID = promotedDisplayID
            ?? displayManager.restorePriorityDisplay(managedVirtualDisplayID: state.virtualDisplayID)?.id else {
            try enterPausedRecoveryKeepingReplacementAlive(reason: "Physical takeover verification failed: no physical display is available.")
            return .pausedForSafety(reason: "No physical display is available.")
        }
        logger.info("Waiting \(timing.effectiveRestorePostPromoteStabilizationMilliseconds)ms before physical takeover verification.")
        let takeoverStarted = clock.uptime
        let takeover = displayManager.verifyPhysicalTakeover(
            displayID: takeoverDisplayID,
            managedVirtualDisplayID: state.virtualDisplayID,
            stabilizationSeconds: stabilizationSeconds
        )
        logger.info("[Perf] physical-takeover durationMs=\(Int((clock.uptime - takeoverStarted) * 1000)) safe=\(takeover.safeToDestroyVirtualDisplay)")
        guard takeover.safeToDestroyVirtualDisplay else {
            try enterPausedRecoveryKeepingReplacementAlive(reason: "Physical takeover verification failed: \(takeover.summary)")
            return .pausedForSafety(reason: takeover.summary)
        }

        try recoveryJournalStore.update { journal in
            journal.cleanupProgress.physicalTakeoverVerified = true
            journal.stage = .cleanupInProgress
        }

        try setPhase(.cleanupInProgress)
        var progress = currentCleanupProgress()
        if state.builtInBrightnessDimmed == true, progress.brightnessRestore != .completed {
            try setPhase(.restoringBrightness)
            guard let originalBrightness = state.originalBrightness else {
                let reason = "Brightness restore is required, but the original built-in display brightness is unavailable. Replacement display and Keep Awake were preserved."
                try enterCleanupRecovery(reason: reason)
                try recoveryJournalStore.update { $0.cleanupProgress.brightnessRestore = .failed }
                return .cleanupIncomplete(progress: currentCleanupProgress(), reason: reason)
            }
            let brightnessRestore = builtInDisplayManager.restoreBrightness(originalBrightness)
            guard brightnessRestore.success else {
                let reason = "Built-in display brightness restore failed. Replacement display and Keep Awake were preserved."
                logger.error("[Safety] \(brightnessRestore.message)")
                try enterCleanupRecovery(reason: reason)
                try recoveryJournalStore.update { $0.cleanupProgress.brightnessRestore = .failed }
                return .cleanupIncomplete(progress: currentCleanupProgress(), reason: reason)
            }
            logger.info(brightnessRestore.message)
            try recoveryJournalStore.update {
                $0.cleanupProgress.brightnessRestore = .completed
                $0.cleanupProgress.brightnessVerification = .completed
            }
        } else if state.builtInBrightnessDimmed != true {
            try recoveryJournalStore.update {
                $0.cleanupProgress.brightnessRestore = .skippedNotRequired
                $0.cleanupProgress.brightnessVerification = .skippedNotRequired
            }
        }

        progress = currentCleanupProgress()
        if progress.virtualHostStop != .completed || progress.virtualDisplayDisappearance != .completed {
            try setPhase(.stoppingVirtualDisplay)
            let virtualCleanup = virtualDisplayManager.destroyVirtualDisplayIfManaged()
            guard virtualCleanup.completed else {
                let reason = "Virtual display cleanup \(virtualCleanup.summary)."
                try enterCleanupRecovery(reason: reason)
                try recoveryJournalStore.update {
                    $0.cleanupProgress.virtualDisplayCleanup = .failed
                    $0.cleanupProgress.virtualHostStop = virtualCleanup.completed ? .completed : .unknown
                    $0.cleanupProgress.virtualDisplayDisappearance = .unknown
                }
                return .cleanupIncomplete(progress: currentCleanupProgress(), reason: reason)
            }
            try recoveryJournalStore.update {
                $0.cleanupProgress.virtualDisplayCleanup = .completed
                $0.cleanupProgress.virtualHostStop = .completed
                $0.cleanupProgress.virtualDisplayDisappearance = .completed
            }
        }

        progress = currentCleanupProgress()
        if progress.keepAwakeHolderStop != .completed || progress.keepAwakeAssertionDisappearance != .completed {
            try setPhase(.stoppingKeepAwake)
            let keepAwakeCleanup = sleepManager.disableKeepAwake()
            guard keepAwakeCleanup.completed else {
                let reason = "Keep Awake cleanup \(keepAwakeCleanup.summary)."
                try enterCleanupRecovery(reason: reason)
                try recoveryJournalStore.update {
                    $0.cleanupProgress.keepAwakeCleanup = .failed
                    $0.cleanupProgress.keepAwakeHolderStop = keepAwakeCleanup.completed ? .completed : .unknown
                    $0.cleanupProgress.keepAwakeAssertionDisappearance = .unknown
                }
                return .cleanupIncomplete(progress: currentCleanupProgress(), reason: reason)
            }
            try recoveryJournalStore.update {
                $0.cleanupProgress.keepAwakeCleanup = .completed
                $0.cleanupProgress.keepAwakeHolderStop = .completed
                $0.cleanupProgress.keepAwakeAssertionDisappearance = .completed
            }
        }

        progress = currentCleanupProgress()
        if progress.touchBarRestore != .completed && progress.touchBarRestore != .skippedNotRequired {
            try setPhase(.restoringTouchBar)
            let touchBarResult = touchBarManager.showIfNeeded(state.touchBarHidden)
            if touchBarResult.success {
                logger.info(touchBarResult.message)
            } else if state.touchBarHidden == true {
                let reason = "Touch Bar restoration could not be confirmed: \(touchBarResult.message)"
                try recoveryJournalStore.update { $0.cleanupProgress.touchBarRestore = .failed }
                try enterCleanupRecovery(reason: reason)
                return .cleanupIncomplete(progress: currentCleanupProgress(), reason: reason)
            }
            try recoveryJournalStore.update {
                $0.cleanupProgress.touchBarRestore = state.touchBarHidden == true
                    ? (touchBarResult.success ? .completed : .failed)
                    : .skippedNotRequired
            }
        }

        let finalSnapshot = processSnapshotProvider.capture()
        let keepAwakeObservation = sleepManager.managedResourceObservation(snapshot: finalSnapshot)
        let virtualObservation = virtualDisplayManager.managedResourceObservation(snapshot: finalSnapshot)
        let managedDisplayStillEnumerated = displayManager.displays().contains { $0.isManagedVirtual }
        guard keepAwakeObservation.status == .none,
              virtualObservation.status == .none,
              !managedDisplayStillEnumerated else {
            let reason = "Final resource verification is incomplete: Keep Awake=\(keepAwakeObservation.status.rawValue), virtual host=\(virtualObservation.status.rawValue), managed display=\(managedDisplayStillEnumerated ? "present" : "absent")."
            try enterCleanupRecovery(reason: reason)
            return .cleanupIncomplete(progress: currentCleanupProgress(), reason: reason)
        }

        let cooldownSeconds = afterPausedRestore ? timing.restoreCooldownAfterPausedSeconds : timing.restoreCooldownSeconds
        let cooldownUntil = clock.now.addingTimeInterval(TimeInterval(cooldownSeconds))
        do {
            try stateStore.transaction { newState in
                Self.resetRuntimeState(&newState, lastError: nil, cooldownUntil: cooldownUntil)
                newState.lastOutcome = afterPausedRestore ? .recoveredWithWarning : .success
                if afterPausedRestore {
                    newState.lastWarning = "Restore completed after pausing for physical display safety."
                }
                newState.phase = .coolingDown
                newState.phaseMessage = RuntimePhase.coolingDown.message
                newState.phaseStartedAt = clock.now
                newState.phaseDeadlineAt = cooldownUntil
                newState.lastProgressAt = clock.now
            }
            try recoveryJournalStore.update { $0.cleanupProgress.runtimeStatePersistence = .completed }
        } catch {
            try? recoveryJournalStore.update { $0.cleanupProgress.runtimeStatePersistence = .failed }
            let reason = "Managed resources were cleaned, but final Normal state persistence failed: \(error.localizedDescription)"
            logger.error("[Safety] \(reason)")
            return .cleanupIncomplete(progress: currentCleanupProgress(), reason: reason)
        }
        let suffix = afterPausedRestore ? " after paused restore" : ""
        let result = evaluateRestoreSuccess(
            result: .completed,
            finalizingJournalOperationID: (try recoveryJournalStore.read())?.operationID,
            processSnapshot: finalSnapshot
        )
        if result.succeeded {
            logger.info("Normal Mode restored\(suffix). Enable cooldown until \(ISO8601DateFormatter().string(from: cooldownUntil)), duration=\(cooldownSeconds)s.")
        }
        return result
    }

    func evaluateRestoreSuccess(
        result: RestoreResult,
        finalizingJournalOperationID: String?,
        precomputedAssessment: CleanNormalAssessment? = nil,
        processSnapshot: ManagedProcessSnapshot? = nil
    ) -> RestoreResult {
        let started = clock.uptime
        let assessment = precomputedAssessment ?? CleanNormalAssessor(
            stateStore: stateStore,
            recoveryJournalStore: recoveryJournalStore,
            sleepManager: sleepManager,
            virtualDisplayManager: virtualDisplayManager,
            displayManager: displayManager,
            snapshotProvider: processSnapshotProvider
        ).assess(
            allowingFinalizingJournalOperationID: finalizingJournalOperationID,
            snapshot: processSnapshot
        )
        guard assessment.isClean else {
            let reason = "Final Restore assessment failed: \(assessment.violations.joined(separator: " "))"
            try? stateStore.transaction { state in
                state.mode = .error
                state.phase = .error
                state.phaseMessage = "Final Restore verification failed."
                state.lastError = reason
                state.lastOutcome = .failed
            }
            logger.error("[Safety] \(reason)")
            return .cleanupIncomplete(progress: currentCleanupProgress(), reason: reason)
        }

        if let finalizingJournalOperationID {
            do {
                guard let journal = try recoveryJournalStore.read(),
                      journal.operationID == finalizingJournalOperationID else {
                    throw CodexHeadlessError.recoveryJournalUnavailable(
                        message: "The expected finalizing Recovery Journal is missing or changed."
                    )
                }
                try recoveryJournalStore.update { journal in
                    journal.cleanupProgress.finalStatePersisted = true
                    journal.cleanupProgress.journalFinalization = .completed
                    journal.stage = .finalStatePersisted
                }
                try recoveryJournalStore.delete()
            } catch {
                try? recoveryJournalStore.update { $0.cleanupProgress.journalFinalization = .failed }
                let reason = "Recovery Journal finalization failed: \(error.localizedDescription)"
                try? stateStore.transaction { state in
                    state.mode = .error
                    state.phase = .error
                    state.phaseMessage = "Recovery Journal finalization is incomplete."
                    state.lastError = reason
                    state.lastOutcome = .failed
                }
                return .cleanupIncomplete(progress: currentCleanupProgress(), reason: reason)
            }
        }

        do {
            let state = try stateStore.read()
            let journalAbsent = try recoveryJournalStore.read() == nil
            let displays = displayManager.displays()
            let physicalMain = displays.contains { !$0.isManagedVirtual && $0.isActive && $0.isOnline && $0.isMain }
            let managedDisplayAbsent = !displays.contains { $0.isManagedVirtual }
            guard state.mode == .normal,
                  !state.keepAwake, state.keepAwakeHost == nil, state.caffeinatePID == nil,
                  !state.virtualDisplayCreated, state.virtualDisplayHost == nil, state.virtualDisplayID == nil,
                  state.builtInSoftDisconnected != true,
                  state.builtInBrightnessDimmed != true,
                  state.touchBarHidden != true,
                  journalAbsent, physicalMain, managedDisplayAbsent else {
                throw CodexHeadlessError.cleanupIncomplete(
                    message: "Final lightweight state, Journal, or display verification failed."
                )
            }
        } catch {
            let reason = "Final post-Journal Restore verification failed: \(error.localizedDescription)"
            try? stateStore.transaction { state in
                state.mode = .error
                state.phase = .error
                state.phaseMessage = "Final Restore verification failed."
                state.lastError = reason
                state.lastOutcome = .failed
            }
            return .cleanupIncomplete(progress: currentCleanupProgress(), reason: reason)
        }
        logger.info("[Perf] restore-final-verification durationMs=\(Int((clock.uptime - started) * 1000)) processSnapshots=1 result=success")
        return result
    }

    func enterCleanupRecovery(reason: String) throws {
        logger.error("[Safety] \(reason) Restore remains resumable; no false Normal state was written.")
        try stateStore.transaction { state in
            state.mode = .restoring
            state.phase = .restorePaused
            state.phaseMessage = "Restore cleanup paused. Run Restore again."
            state.phaseStartedAt = clock.now
            state.phaseDeadlineAt = nil
            state.lastProgressAt = clock.now
            state.lastError = reason
            state.lastOutcome = .pausedForSafety
        }
    }

    func safeRestoreLocked(reason: String) throws -> RestoreResult {
        logger.error("[SafeRestore] Runtime state is damaged: \(reason)")
        let journal: RecoveryJournal
        do {
            guard let loaded = try recoveryJournalStore.read() else {
                let message = "Runtime state is damaged and no recovery journal is available. Managed processes were preserved."
                let recovery = RuntimeState.recoveryRequired(message: message, now: clock.now)
                try stateStore.replaceCorruptedStateAfterVerifiedRecovery(recovery)
                return .recoveryRequired(reason: message)
            }
            journal = loaded
        } catch {
            let message = "Runtime state and recovery journal are both unavailable: \(error.localizedDescription). Managed processes were preserved."
            let recovery = RuntimeState.recoveryRequired(message: message, now: clock.now)
            try stateStore.replaceCorruptedStateAfterVerifiedRecovery(recovery)
            return .recoveryRequired(reason: message)
        }
        var displays = displayManager.displays()
        var managedDisplay = displays.first { $0.isManagedVirtual }
        let virtualRecord = journal.virtualDisplayHost
        let keepAwakeRecord = journal.keepAwakeHost

        if journal.builtInSoftDisconnected {
            let result = builtInDisplayManager.restoreBuiltInDisplay(displayID: journal.builtInDisplayID)
            guard result.success else {
                let message = "Recovery journal identified a soft-disconnected built-in display, but restore failed: \(result.message)"
                var recovery = RuntimeState.recoveryRequired(message: message, now: clock.now)
                recovery.builtInSoftDisconnected = true
                recovery.softDisconnectedDisplayID = journal.builtInDisplayID
                recovery.virtualDisplayHost = virtualRecord
                recovery.keepAwakeHost = keepAwakeRecord
                try stateStore.replaceCorruptedStateAfterVerifiedRecovery(recovery)
                return .recoveryRequired(reason: message)
            }
            if let id = journal.builtInDisplayID {
                _ = displayManager.waitForDisplay(id: id, present: true, timeoutSeconds: TimeInterval(restoreTiming().restoreBuiltInShortWaitSeconds))
            }
            displays = displayManager.displays()
            managedDisplay = displays.first { $0.isManagedVirtual }
        }

        if managedDisplay != nil, virtualRecord == nil {
            var recovery = RuntimeState.recoveryRequired(
                message: "A managed virtual display is visible but its process ownership cannot be verified. Resources were preserved.",
                now: clock.now
            )
            recovery.virtualDisplayCreated = true
            recovery.virtualDisplayID = managedDisplay?.id
            recovery.keepAwake = keepAwakeRecord != nil
            recovery.keepAwakeHost = keepAwakeRecord
            recovery.caffeinatePID = keepAwakeRecord?.pid
            recovery.keepAwakeBackend = keepAwakeRecord?.backend.rawValue
            try stateStore.replaceCorruptedStateAfterVerifiedRecovery(recovery)
            return .recoveryRequired(reason: recovery.lastError ?? "Virtual display ownership is unknown.")
        }

        var recovery = RuntimeState.default
        recovery.mode = .restoring
        recovery.phase = .restoringBuiltInDisplay
        recovery.phaseMessage = "Safe Restore is recovering from damaged runtime state."
        recovery.phaseStartedAt = clock.now
        recovery.lastProgressAt = clock.now
        recovery.lastOutcome = .pausedForSafety
        recovery.virtualDisplayCreated = managedDisplay != nil || virtualRecord != nil
        recovery.virtualDisplayID = managedDisplay?.id
        recovery.virtualDisplayPID = virtualRecord?.pid
        recovery.virtualDisplayHost = virtualRecord
        recovery.keepAwake = keepAwakeRecord != nil
        recovery.keepAwakeHost = keepAwakeRecord
        recovery.caffeinatePID = keepAwakeRecord?.pid
        recovery.keepAwakeBackend = keepAwakeRecord?.backend.rawValue
        recovery.touchBarHidden = journal.touchBarHidden == true
        recovery.builtInDisplayID = journal.builtInDisplayID
        recovery.builtInWasMain = journal.builtInWasMain
        recovery.builtInSoftDisconnected = journal.builtInSoftDisconnected
        recovery.softDisconnectedDisplayID = journal.builtInDisplayID
        recovery.replacementDisplayID = journal.replacementDisplayID
        recovery.replacementDisplayType = journal.replacementDisplayType

        guard let physical = displays.first(where: {
            !$0.isManagedVirtual && $0.isActive && $0.isOnline
        }) else {
            recovery.phase = .restorePaused
            recovery.phaseMessage = RuntimePhase.restorePaused.message
            recovery.lastError = "Safe Restore paused because no physical display is available."
            try stateStore.replaceCorruptedStateAfterVerifiedRecovery(recovery)
            return .pausedForSafety(reason: recovery.lastError!)
        }

        do {
            if !physical.isMain {
                guard try displayManager.setMainDisplay(id: physical.id, reason: "Safe Restore physical display") else {
                    throw CodexHeadlessError.displayHandoffFailed(message: "Physical display promotion returned false.")
                }
            }
        } catch {
            recovery.phase = .restorePaused
            recovery.phaseMessage = RuntimePhase.restorePaused.message
            recovery.lastError = "Safe Restore could not promote the physical display: \(error.localizedDescription)"
            try stateStore.replaceCorruptedStateAfterVerifiedRecovery(recovery)
            return .pausedForSafety(reason: recovery.lastError!)
        }

        let verification = displayManager.verifyPhysicalTakeover(
            displayID: physical.id,
            managedVirtualDisplayID: managedDisplay?.id,
            stabilizationSeconds: 0.5
        )
        guard verification.safeToDestroyVirtualDisplay else {
            recovery.phase = .restorePaused
            recovery.phaseMessage = RuntimePhase.restorePaused.message
            recovery.lastError = "Safe Restore physical takeover verification failed: \(verification.summary)"
            try stateStore.replaceCorruptedStateAfterVerifiedRecovery(recovery)
            return .pausedForSafety(reason: recovery.lastError!)
        }

        try stateStore.replaceCorruptedStateAfterVerifiedRecovery(recovery)
        logger.info("[SafeRestore] Rebuilt a trusted recovery state after physical takeover verification.")
        return try finishRestoreAfterPhysicalDisplayAvailable(state: recovery, afterPausedRestore: true)
    }

    func ensureRecoveryJournalForRestore(state: RuntimeState) throws {
        do {
            if try recoveryJournalStore.read() != nil { return }
        } catch let journalError as RecoveryJournalStoreError {
            throw journalError
        } catch {
            // RuntimeState is not an independent trust root. Preserve the damaged
            // journal and require an explicit, independently verified repair path.
            throw error
        }
        guard state.mode != .normal || state.keepAwake || state.virtualDisplayCreated else { return }
        if state.keepAwake || state.keepAwakeHost != nil || state.caffeinatePID != nil
            || state.virtualDisplayCreated || state.virtualDisplayHost != nil || state.virtualDisplayPID != nil {
            throw CodexHeadlessError.recoveryJournalUnavailable(
                message: "RuntimeState records managed processes but Recovery Journal is missing. RuntimeState is not an independent ownership root; resources were preserved."
            )
        }
        _ = try recoveryJournalStore.create(operationID: "restore-legacy-\(UUID().uuidString.lowercased())")
        try recoveryJournalStore.update { journal in
            journal.builtInDisplayID = state.softDisconnectedDisplayID ?? state.builtInDisplayID
            journal.builtInWasMain = state.builtInWasMain
            journal.builtInSoftDisconnected = state.builtInSoftDisconnected == true
            journal.softDisconnectMethod = state.builtInSoftDisconnectMethod
            journal.replacementDisplayID = state.replacementDisplayID ?? state.virtualDisplayID
            journal.replacementDisplayType = state.replacementDisplayType
            journal.virtualDisplayHost = state.virtualDisplayHost
            journal.keepAwakeHost = state.keepAwakeHost
            journal.stage = .restoringPhysicalDisplay
        }
    }

    func currentCleanupProgress() -> RestoreCleanupProgress {
        do {
            return try recoveryJournalStore.read()?.cleanupProgress ?? RestoreCleanupProgress()
        } catch {
            return RestoreCleanupProgress()
        }
    }

    func waitForRestorePriorityDisplayDuringGrace(
        managedVirtualDisplayID: UInt32?,
        timing: TimingConfig
    ) throws -> DisplayInfo? {
        let graceSeconds = timing.effectiveRestorePhysicalDisplayGraceSeconds
        guard graceSeconds > 0 else {
            logger.info("Final grace polling is disabled.")
            return nil
        }

        let pollIntervalMilliseconds = max(50, timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds)
        let deadline = clock.now.addingTimeInterval(TimeInterval(graceSeconds))
        let uptimeDeadline = clock.uptime + TimeInterval(graceSeconds)
        try stateStore.transaction { state in
            state.phase = .waitingForPhysicalDisplay
            state.phaseMessage = "Final check for a physical display..."
            state.phaseStartedAt = clock.now
            state.phaseDeadlineAt = deadline
            state.lastProgressAt = clock.now
        }
        logger.info("[Phase] waitingForPhysicalDisplay, grace=\(graceSeconds)s, pollInterval=\(pollIntervalMilliseconds)ms")

        while clock.uptime < uptimeDeadline {
            if let display = displayManager.restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID) {
                logger.info("Physical display became available during grace polling; continuing restore without entering paused state.")
                return display
            }
            clock.sleep(seconds: Double(pollIntervalMilliseconds) / 1000.0)
        }

        return displayManager.restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID)
    }

    func restoreSavedDisplayLayout(managedVirtualDisplayID: UInt32?) {
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

}
