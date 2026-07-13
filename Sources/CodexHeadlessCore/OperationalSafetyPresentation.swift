import Foundation

public enum OperationalSafetyPresentation: Equatable {
    case normalClean, normalTemporarilyUnavailable(String), normalRestoreRequired(String), normalRecoveryRequired(String), normalUnableToVerify(String)
    case preparing, awaitingConfirmation, headlessManaged, restoring, fallback(String), error(String), recoveryRequired(String), unableToVerify(String)

    public static func makeNormal(_ assessment: CleanNormalAssessment?) -> Self {
        guard let assessment else { return .normalUnableToVerify("Normal readiness has not been assessed.") }
        switch assessment.classification {
        case .clean: return .normalClean
        case .temporarilyUnavailable: return .normalTemporarilyUnavailable(assessment.recommendedAction)
        case .resourceDirty: return .normalRestoreRequired(assessment.recommendedAction)
        case .recoveryRequired: return .normalRecoveryRequired(assessment.recommendedAction)
        case .unknown: return .normalUnableToVerify(assessment.recommendedAction)
        }
    }

    public static func make(state: RuntimeState, availability: OperationalEvidenceAvailability) -> Self {
        if state.mode == .normal { return .normalUnableToVerify("Normal mode requires a Clean Normal assessment.") }
        switch availability {
        case .unavailable(let reason): return .unableToVerify(reason ?? "Operational evidence is unavailable.")
        case .stale: return .unableToVerify("Operational evidence is stale; wait for reconciliation or run Doctor.")
        case .fresh(let evidence), .refreshing(let evidence?): return fromFresh(state: state, evidence: evidence)
        case .refreshing(lastCompleted: nil): return state.mode == .restoring ? .restoring : .unableToVerify("Operational evidence is being collected.")
        }
    }

    private static func fromFresh(state: RuntimeState, evidence: OperationalEvidence) -> Self {
        if state.mode == .recoveryRequired { return .recoveryRequired(state.lastError ?? "Recovery is required.") }
        if state.mode == .error { return .error(state.lastError ?? "Review status.") }
        let recoveryViolation = evidence.violations.first { violation in
            switch violation {
            case .journalMissing, .journalInconsistent, .managedDisplayMissing, .managedDisplayIDMismatch,
                 .replacementDisplayMissing, .confirmationStateMismatch, .builtInStateMismatch: true
            default: false
            }
        }
        if let recoveryViolation { return .recoveryRequired(String(describing: recoveryViolation)) }
        if !evidence.violations.isEmpty { return .unableToVerify(String(describing: evidence.violations[0])) }
        switch state.mode {
        case .preparing: return .preparing
        case .confirmRequired: return .awaitingConfirmation
        case .headless: return .headlessManaged
        case .restoring: return .restoring
        case .fallback: return .fallback(state.lastWarning ?? "Review status.")
        case .error: return .error(state.lastError ?? "Review status.")
        case .recoveryRequired: return .recoveryRequired(state.lastError ?? "Recovery is required.")
        case .normal: return .normalUnableToVerify("Normal mode requires Clean Normal.")
        }
    }

    public var title: String {
        switch self {
        case .normalClean: "Clean Normal"
        case .normalTemporarilyUnavailable: "Display unavailable - wake the screen"
        case .normalRestoreRequired: "Restore Required"
        case .normalRecoveryRequired, .recoveryRequired: "Recovery Required"
        case .normalUnableToVerify, .unableToVerify: "Unable to verify"
        case .preparing: "Preparing managed handoff"
        case .awaitingConfirmation: "Awaiting confirmation"
        case .headlessManaged: "Managed Headless active"
        case .restoring: "Restoring Normal"
        case .fallback: "Fallback active - review status"
        case .error: "Error - review status"
        }
    }
    public var normalReadinessText: String {
        switch self {
        case .normalClean: CleanNormalClassification.clean.rawValue
        case .normalTemporarilyUnavailable: CleanNormalClassification.temporarilyUnavailable.rawValue
        case .normalRestoreRequired: CleanNormalClassification.resourceDirty.rawValue
        case .normalRecoveryRequired: CleanNormalClassification.recoveryRequired.rawValue
        case .normalUnableToVerify: CleanNormalClassification.unknown.rawValue
        default: "Not applicable while \(title)"
        }
    }
    public var recommendedAction: String {
        switch self {
        case .normalClean: "System is ready for Enable."
        case .normalTemporarilyUnavailable(let s), .normalRestoreRequired(let s), .normalRecoveryRequired(let s), .normalUnableToVerify(let s), .unableToVerify(let s): s
        case .preparing: "Wait for managed handoff to complete."
        case .awaitingConfirmation: "Confirm the display state, or Restore when desired."
        case .headlessManaged: "Continue Headless, or Restore when desired."
        case .restoring: "Wait for verified Clean Normal restoration."
        case .fallback(let s), .error(let s), .recoveryRequired(let s): s
        }
    }
}
