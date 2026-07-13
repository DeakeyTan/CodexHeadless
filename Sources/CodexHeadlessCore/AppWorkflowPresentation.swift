import Foundation

public enum AppEnableFailurePresentation: Equatable {
    case normalPreserved(message: String)
    case normalRestored(message: String)
    case pausedWithReplacement(message: String)
    case recoveryRequired(message: String)
    case unsafeFailure(message: String)

    public static func make(outcome: FailureSafetyOutcome, message: String) -> Self {
        switch outcome {
        case .normalPreserved: .normalPreserved(message: message)
        case .normalRestored: .normalRestored(message: message)
        case .pausedWithReplacement: .pausedWithReplacement(
            message: "\(message) Restore is safely paused; the replacement display and Keep Awake remain active."
        )
        case .recoveryRequired: .recoveryRequired(
            message: "\(message) Recovery is required. Run `codex-headless off` and consult the Recovery Guide."
        )
        case .unsafeFailure: .unsafeFailure(message: message)
        }
    }

    public var shouldMarkError: Bool {
        if case .unsafeFailure = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case .normalPreserved(let message), .normalRestored(let message),
             .pausedWithReplacement(let message), .recoveryRequired(let message),
             .unsafeFailure(let message): message
        }
    }
}

public enum AppRestorePresentation: Equatable {
    case completed(message: String)
    case alreadyNormal(message: String)
    case pausedForSafety(message: String)
    case recoveryRequired(message: String)
    case cleanupIncomplete(message: String)
    case failed(message: String)

    public static func make(result: RestoreResult) -> Self {
        switch result {
        case .completed: .completed(message: result.message)
        case .alreadyNormal: .alreadyNormal(message: result.message)
        case .pausedForSafety: .pausedForSafety(message: result.message)
        case .recoveryRequired: .recoveryRequired(message: result.message)
        case .cleanupIncomplete: .cleanupIncomplete(message: result.message)
        case .failed: .failed(message: result.message)
        }
    }

    public var message: String {
        switch self {
        case .completed(let message), .alreadyNormal(let message), .pausedForSafety(let message),
             .recoveryRequired(let message), .cleanupIncomplete(let message), .failed(let message): message
        }
    }

    public var isSuccess: Bool {
        switch self {
        case .completed, .alreadyNormal: true
        case .pausedForSafety, .recoveryRequired, .cleanupIncomplete, .failed: false
        }
    }
}

public struct AppTerminationSnapshot {
    public var state: RuntimeState
    public var recoveryJournalActive: Bool
    public var operationBusy: Bool

    public init(state: RuntimeState, recoveryJournalActive: Bool, operationBusy: Bool) {
        self.state = state
        self.recoveryJournalActive = recoveryJournalActive
        self.operationBusy = operationBusy
    }
}

public enum AppTerminationGate {
    public static func blockReason(_ snapshot: AppTerminationSnapshot) -> String? {
        let state = snapshot.state
        let resourcesActive = state.keepAwake || state.virtualDisplayCreated
            || state.keepAwakeHost != nil || state.virtualDisplayHost != nil
        guard state.mode == .normal,
              !resourcesActive,
              !snapshot.recoveryJournalActive,
              !snapshot.operationBusy,
              state.phase != .cleanupInProgress else {
            return "CodexHeadless is protecting an active workflow, Recovery Journal, virtual display, or Keep Awake resource. Restore Normal Mode and wait for cleanup to finish before quitting."
        }
        return nil
    }
}
