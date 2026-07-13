import Foundation

public struct OperationalEvidenceAssessor {
    private let stateStore: RuntimeStateStoring
    private let journalStore: RecoveryJournalStoring
    private let sleepManager: SleepManaging
    private let virtualManager: VirtualDisplayManaging
    private let displayManager: DisplayManaging
    private let snapshotProvider: ManagedProcessSnapshotProviding

    public init(stateStore: RuntimeStateStoring, journalStore: RecoveryJournalStoring, sleepManager: SleepManaging, virtualManager: VirtualDisplayManaging, displayManager: DisplayManaging, snapshotProvider: ManagedProcessSnapshotProviding = ManagedProcessSnapshotProvider()) {
        self.stateStore = stateStore; self.journalStore = journalStore; self.sleepManager = sleepManager
        self.virtualManager = virtualManager; self.displayManager = displayManager; self.snapshotProvider = snapshotProvider
    }

    public func assess(state suppliedState: RuntimeState? = nil, snapshot suppliedSnapshot: ManagedProcessSnapshot? = nil, displays suppliedDisplays: [DisplayInfo]? = nil, source: OperationalEvidenceSource) -> OperationalEvidence {
        var violations: [OperationalEvidenceViolation] = []
        let state: RuntimeState
        let runtimeStatus: EvidenceReadStatus
        if let suppliedState { state = suppliedState; runtimeStatus = .success }
        else { do { state = try stateStore.read(); runtimeStatus = .success } catch { state = .recoveryRequired(message: error.localizedDescription); runtimeStatus = .failed(error.localizedDescription); violations.append(.runtimeUnreadable(error.localizedDescription)) } }

        let snapshot = suppliedSnapshot ?? snapshotProvider.capture()
        let processEvidence: OperationalProcessSnapshotEvidence
        if snapshot.succeeded { processEvidence = .success(durationMilliseconds: snapshot.durationMilliseconds) }
        else { let reason = snapshot.error ?? "process snapshot failed"; processEvidence = .failed(reason); violations.append(.processSnapshotFailed(reason)) }
        let displays = suppliedDisplays ?? displayManager.displays()
        let keepAwake = sleepManager.managedResourceObservation(snapshot: snapshot)
        let virtual = virtualManager.managedResourceObservation(snapshot: snapshot)

        let journalEvidence: OperationalJournalEvidence
        var activeJournal: RecoveryJournal?
        var operationID: String?
        do {
            if let journal = try journalStore.read() {
                activeJournal = journal
                operationID = journal.operationID
                if let reason = journalConsistencyViolation(journal: journal, state: state) {
                    journalEvidence = .activeInconsistent(reason); violations.append(.journalInconsistent(reason))
                } else { journalEvidence = .activeConsistent(operationID: journal.operationID, stage: journal.stage) }
            } else if state.mode == .normal { journalEvidence = .notExpected }
            else { journalEvidence = .missingWhenRequired; violations.append(.journalMissing) }
        } catch { journalEvidence = .unreadable(error.localizedDescription); violations.append(.journalUnreadable(error.localizedDescription)) }

        let preparingRequiresKeepAwake = state.mode == .preparing && activeJournal.map { journalStageRequiresKeepAwake($0.stage) } == true
        if (state.mode == .confirmRequired || state.mode == .headless), !state.keepAwake {
            violations.append(.keepAwakeStateMismatch)
        }
        if (preparingRequiresKeepAwake || state.mode == .confirmRequired || state.mode == .headless) && keepAwake.status != .verifiedOwned {
            violations.append(.keepAwakeNotVerified(keepAwake.status))
        }
        let preparingRequiresVirtual = state.mode == .preparing && activeJournal?.virtualDisplayResource != nil
        if (state.virtualDisplayCreated || preparingRequiresVirtual) && virtual.status != .verifiedOwned { violations.append(.virtualDisplayNotVerified(virtual.status)) }
        let observedManaged = state.virtualDisplayID.flatMap { expected in displays.first { $0.id == expected } }
        if state.virtualDisplayCreated && observedManaged == nil { violations.append(.managedDisplayMissing(state.virtualDisplayID)) }
        if let expected = state.virtualDisplayID, let observedManaged, !observedManaged.isManagedVirtual {
            violations.append(.managedDisplayMissing(expected))
        }
        if let expected = state.virtualDisplayID, observedManaged?.id != expected {
            violations.append(.managedDisplayIDMismatch(expected: expected, observed: observedManaged?.id))
        }
        let replacement = state.replacementDisplayID.flatMap { expected in displays.first { $0.id == expected } }
        if state.mode == .confirmRequired || state.mode == .headless {
            if replacement == nil { violations.append(.replacementDisplayMissing(state.replacementDisplayID)) }
            else if replacement?.isActive != true || replacement?.isOnline != true {
                violations.append(.replacementDisplayMissing(replacement!.id))
            }
        }
        if state.mode == .confirmRequired {
            if state.confirmationRequired != true || state.rollbackConfirmed || state.rollbackDeadline == nil {
                violations.append(.confirmationStateMismatch("Confirm Required must have confirmationRequired=true, rollbackConfirmed=false, and an active deadline."))
            }
        }
        if state.mode == .headless, state.confirmationRequired == true || !state.rollbackConfirmed || state.rollbackDeadline != nil {
            violations.append(.confirmationStateMismatch("Headless must have confirmationRequired=false, rollbackConfirmed=true, and no rollback deadline."))
        }
        if (state.mode == .confirmRequired || state.mode == .headless), state.builtInSoftDisconnected == true, displays.contains(where: { $0.isBuiltIn }) {
            violations.append(.builtInStateMismatch("RuntimeState records the built-in display as soft-disconnected, but it is still enumerated."))
        }
        let displayEvidence = OperationalDisplayEvidence(
            expectedManagedDisplayID: state.virtualDisplayID, observedManagedDisplayID: observedManaged?.id,
            managedDisplayEnumerated: observedManaged != nil,
            expectedDisplayMatchesObserved: state.virtualDisplayID.map { $0 == observedManaged?.id },
            physicalMainDisplayID: displays.first { $0.isMain && !$0.isManagedVirtual }?.id,
            builtInPresent: displays.contains { $0.isBuiltIn },
            expectedReplacementDisplayID: state.replacementDisplayID,
            replacementDisplayEnumerated: replacement != nil,
            replacementDisplayActive: replacement?.isActive == true,
            replacementDisplayOnline: replacement?.isOnline == true,
            replacementDisplayMain: replacement?.isMain == true,
            replacementDisplayManagedVirtual: replacement?.isManagedVirtual == true
        )
        return .init(capturedAt: Date(), source: source, runtimeMode: state.mode, operationID: operationID,
                     phase: RuntimePhaseFormatter.phase(state), runtimeReadStatus: runtimeStatus, journal: journalEvidence,
                     processSnapshot: processEvidence, keepAwake: keepAwake, virtualDisplay: virtual,
                     display: displayEvidence, violations: violations)
    }

    private func journalStageRequiresKeepAwake(_ stage: RecoveryJournalStage) -> Bool {
        switch stage {
        case .enabling: return false
        case .keepAwakeStarted, .virtualDisplayStarted, .replacementReady, .handoffCommitted, .builtInSoftDisconnected, .headless,
             .restoringPhysicalDisplay, .cleanupInProgress, .finalStatePersisted, .recoveryRequired: return true
        }
    }

    private func journalConsistencyViolation(journal: RecoveryJournal, state: RuntimeState) -> String? {
        let allowed: Set<RecoveryJournalStage>
        switch state.mode {
        case .preparing: allowed = [.enabling, .keepAwakeStarted, .virtualDisplayStarted, .replacementReady, .handoffCommitted, .builtInSoftDisconnected]
        case .confirmRequired, .headless: allowed = [.handoffCommitted, .builtInSoftDisconnected, .headless]
        case .restoring: allowed = [.restoringPhysicalDisplay, .cleanupInProgress, .finalStatePersisted, .recoveryRequired]
        case .fallback, .error, .recoveryRequired: return nil
        case .normal: return "Journal is active while RuntimeState is Normal."
        }
        guard allowed.contains(journal.stage) else { return "Journal stage \(journal.stage.rawValue) is inconsistent with \(state.mode.rawValue)." }
        if state.virtualDisplayCreated, let expected = state.virtualDisplayID, journal.virtualDisplayResource?.displayID != expected { return "Journal and RuntimeState managed display IDs differ." }
        if state.replacementDisplayID != journal.replacementDisplayID { return "Journal and RuntimeState replacement display IDs differ." }
        if state.builtInSoftDisconnected == true && !journal.builtInSoftDisconnected { return "Journal and RuntimeState built-in handling differ." }
        if (state.mode == .confirmRequired || state.mode == .headless), journal.keepAwakeResource == nil && journal.keepAwakeHost == nil { return "Journal has no Keep Awake ownership record." }
        return nil
    }
}
