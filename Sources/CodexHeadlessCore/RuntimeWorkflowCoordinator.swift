import Foundation

extension HeadlessController {
    @discardableResult
    public func confirm() -> Bool {
        let operation: WorkflowOperationLeaseHandling
        do {
            operation = try operationLock.acquire(name: "confirm")
        } catch {
            logger.error("Confirm could not acquire the workflow lock: \(error.localizedDescription)")
            return false
        }
        defer { operation.release() }

        do {
            let state = try stateStore.read()
            guard state.mode == .confirmRequired else {
                logger.info("Confirm ignored: current mode is \(state.mode.rawValue).")
                return false
            }
            try stateStore.transaction { state in
                guard state.mode == .confirmRequired else { return }
                state.mode = .headless
                state.confirmationRequired = false
                state.rollbackConfirmed = true
                state.rollbackDeadline = nil
                state.phase = .headlessActive
                state.phaseMessage = RuntimePhase.headlessActive.message
                state.phaseStartedAt = clock.now
                state.phaseDeadlineAt = nil
                state.lastProgressAt = clock.now
                state.lastOutcome = .success
            }
            logger.info("Rollback guard confirmed.")
            return true
        } catch {
            logger.error("Confirm failed to persist state: \(error.localizedDescription)")
            return false
        }
    }

    public func rollbackIfNeeded() {
        let operation: WorkflowOperationLeaseHandling
        do {
            operation = try operationLock.acquire(name: "rollback", timeoutSeconds: 0.1, logLifecycle: false)
        } catch {
            return
        }
        defer { operation.release() }

        do {
            let state = try stateStore.read()
            guard !state.rollbackConfirmed,
                  let deadline = state.rollbackDeadline,
                deadline <= clock.now else { return }
            logger.warn("Rollback deadline expired. Restoring Normal Mode.")
            _ = try restoreNormalLocked(markRollbackExpired: true)
        } catch {
            logger.error("Rollback stopped safely: \(error.localizedDescription)")
        }
    }

    public func syncKeepAwakeWithState() {
        guard let operation = try? operationLock.acquire(name: "reconcile-keep-awake", timeoutSeconds: 0.1, logLifecycle: false) else { return }
        defer { operation.release() }
        sleepManager.syncWithState()
    }

    public func syncVirtualDisplayState() {
        guard let operation = try? operationLock.acquire(name: "reconcile-virtual-display", timeoutSeconds: 0.1, logLifecycle: false) else { return }
        defer { operation.release() }
        virtualDisplayManager.reconcileManagedVirtualDisplayIfNeeded()
    }

    public func reconcileAndAssessOperationalEvidence(source: OperationalEvidenceSource) throws -> OperationalEvidence {
        let operation: WorkflowOperationLeaseHandling
        do { operation = try operationLock.acquire(name: "reconcile-operational-evidence", timeoutSeconds: 2, logLifecycle: false) }
        catch { throw CodexHeadlessError.managedResource(message: "Operational evidence refresh could not acquire the workflow lock.") }
        defer { operation.release() }
        let snapshot = processSnapshotProvider.capture()
        let displays = displayManager.displays()
        sleepManager.syncWithState()
        virtualDisplayManager.reconcileManagedVirtualDisplayIfNeeded(displays: displays)
        return OperationalEvidenceAssessor(
            stateStore: stateStore, journalStore: recoveryJournalStore,
            sleepManager: sleepManager, virtualManager: virtualDisplayManager,
            displayManager: displayManager, snapshotProvider: processSnapshotProvider
        ).assess(snapshot: snapshot, displays: displays, source: source)
    }

    public func refreshPhaseIfNeeded() {
        guard let operation = try? operationLock.acquire(name: "refresh-phase", timeoutSeconds: 0.1, logLifecycle: false) else { return }
        defer { operation.release() }
        let state = stateStore.load()
        guard state.mode == .normal,
              state.phase == .coolingDown,
              RuntimePhaseFormatter.cooldownRemainingSeconds(state) == 0 else {
            return
        }

        stateStore.bestEffortUpdate { newState in
            newState.phase = .idle
            newState.phaseMessage = RuntimePhase.idle.message
            newState.phaseStartedAt = clock.now
            newState.phaseDeadlineAt = nil
            newState.lastProgressAt = clock.now
        }
        logger.info("[Phase] idle")
    }

    public func setKeepAwake(_ enabled: Bool) throws {
        let operation = try operationLock.acquire(name: enabled ? "enable-keep-awake" : "disable-keep-awake")
        defer { operation.release() }
        let state = try stateStore.read()
        if enabled {
            try sleepManager.enableKeepAwake()
        } else {
            guard state.mode == .normal else {
                throw CodexHeadlessError.keepAwakeInvariant(
                    message: "Keep Awake cannot be disabled while \(state.mode.rawValue) depends on it. Restore Normal Mode first."
                )
            }
            let result = sleepManager.disableKeepAwake()
            guard result.completed else {
                throw CodexHeadlessError.managedResource(message: "Keep Awake cleanup \(result.summary).")
            }
        }
    }

    public func requestEnableCancellation() throws {
        setInProcessEnableCancellation(true)
        do {
            try stateStore.transaction { $0.enableCancellationRequested = true }
        } catch {
            logger.error("Enable cancellation was retained in-process but could not be persisted: \(error.localizedDescription)")
            throw error
        }
    }

    func isEnableCancellationRequested() -> Bool {
        cancellationLock.lock()
        let inProcess = enableCancellationRequestedInProcess
        cancellationLock.unlock()
        if inProcess { return true }
        return (try? stateStore.read().enableCancellationRequested) == true
    }

    func setInProcessEnableCancellation(_ requested: Bool) {
        cancellationLock.lock()
        enableCancellationRequestedInProcess = requested
        cancellationLock.unlock()
    }

}
