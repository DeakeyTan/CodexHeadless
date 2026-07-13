import Foundation

public enum OperationalEvidenceSource: String, Equatable { case launch, enableCompletion, confirmCompletion, periodicReconcile, restoreStarted, restoreCompletion, explicitStatus, explicitDoctor }
public enum EvidenceReadStatus: Equatable { case success; case failed(String) }
public enum OperationalJournalEvidence: Equatable {
    case notExpected
    case activeConsistent(operationID: String, stage: RecoveryJournalStage)
    case activeInconsistent(String)
    case missingWhenRequired
    case unreadable(String)
}
public enum OperationalProcessSnapshotEvidence: Equatable { case success(durationMilliseconds: Int); case failed(String) }
public struct OperationalDisplayEvidence: Equatable {
    public var expectedManagedDisplayID: UInt32?
    public var observedManagedDisplayID: UInt32?
    public var managedDisplayEnumerated: Bool
    public var expectedDisplayMatchesObserved: Bool?
    public var physicalMainDisplayID: UInt32?
    public var builtInPresent: Bool
    public var expectedReplacementDisplayID: UInt32?
    public var replacementDisplayEnumerated: Bool
    public var replacementDisplayActive: Bool
    public var replacementDisplayOnline: Bool
    public var replacementDisplayMain: Bool
    public var replacementDisplayManagedVirtual: Bool

    public init(
        expectedManagedDisplayID: UInt32?, observedManagedDisplayID: UInt32?, managedDisplayEnumerated: Bool,
        expectedDisplayMatchesObserved: Bool?, physicalMainDisplayID: UInt32?, builtInPresent: Bool,
        expectedReplacementDisplayID: UInt32? = nil, replacementDisplayEnumerated: Bool = false,
        replacementDisplayActive: Bool = false, replacementDisplayOnline: Bool = false,
        replacementDisplayMain: Bool = false, replacementDisplayManagedVirtual: Bool = false
    ) {
        self.expectedManagedDisplayID = expectedManagedDisplayID
        self.observedManagedDisplayID = observedManagedDisplayID
        self.managedDisplayEnumerated = managedDisplayEnumerated
        self.expectedDisplayMatchesObserved = expectedDisplayMatchesObserved
        self.physicalMainDisplayID = physicalMainDisplayID
        self.builtInPresent = builtInPresent
        self.expectedReplacementDisplayID = expectedReplacementDisplayID
        self.replacementDisplayEnumerated = replacementDisplayEnumerated
        self.replacementDisplayActive = replacementDisplayActive
        self.replacementDisplayOnline = replacementDisplayOnline
        self.replacementDisplayMain = replacementDisplayMain
        self.replacementDisplayManagedVirtual = replacementDisplayManagedVirtual
    }
}
public enum OperationalEvidenceViolation: Equatable {
    case runtimeUnreadable(String), journalUnreadable(String), journalMissing, journalInconsistent(String)
    case keepAwakeNotVerified(ManagedResourceObservationStatus)
    case keepAwakeStateMismatch
    case virtualDisplayNotVerified(ManagedResourceObservationStatus)
    case managedDisplayMissing(UInt32?), managedDisplayIDMismatch(expected: UInt32, observed: UInt32?)
    case replacementDisplayMissing(UInt32?), confirmationStateMismatch(String)
    case processSnapshotFailed(String), builtInStateMismatch(String)
}
public struct OperationalEvidence: Equatable {
    public var capturedAt: Date
    public var source: OperationalEvidenceSource
    public var runtimeMode: HeadlessMode
    public var operationID: String?
    public var phase: RuntimePhase
    public var runtimeReadStatus: EvidenceReadStatus
    public var journal: OperationalJournalEvidence
    public var processSnapshot: OperationalProcessSnapshotEvidence
    public var keepAwake: ManagedResourceObservation
    public var virtualDisplay: ManagedResourceObservation
    public var display: OperationalDisplayEvidence
    public var violations: [OperationalEvidenceViolation]
}

public struct ReplacementLossSuspect: Equatable {
    public var runtimeMode: HeadlessMode
    public var operationID: String
    public var replacementDisplayID: UInt32

    public init?(state: RuntimeState, evidence: OperationalEvidence) {
        guard state.mode == .confirmRequired || state.mode == .headless,
              state.mode == evidence.runtimeMode,
              let operationID = evidence.operationID,
              let replacementDisplayID = state.replacementDisplayID,
              evidence.display.expectedReplacementDisplayID == replacementDisplayID,
              evidence.runtimeReadStatus == .success,
              case .success = evidence.processSnapshot,
              case .activeConsistent = evidence.journal,
              evidence.violations.contains(.replacementDisplayMissing(replacementDisplayID)) else { return nil }
        if state.virtualDisplayCreated {
            guard state.virtualDisplayID == replacementDisplayID,
                  evidence.virtualDisplay.status == .verifiedOwned || evidence.virtualDisplay.status == .none else { return nil }
        }
        self.runtimeMode = state.mode
        self.operationID = operationID
        self.replacementDisplayID = replacementDisplayID
    }

    public func stillMatches(state: RuntimeState, evidence: OperationalEvidence) -> Bool {
        ReplacementLossSuspect(state: state, evidence: evidence) == self
    }
}

public enum OperationalEvidenceAvailability: Equatable {
    case fresh(OperationalEvidence)
    case refreshing(lastCompleted: OperationalEvidence?)
    case stale(OperationalEvidence)
    case unavailable(String?)

    public var evidence: OperationalEvidence? {
        switch self { case .fresh(let e), .stale(let e): e; case .refreshing(let e): e; case .unavailable: nil }
    }
}
