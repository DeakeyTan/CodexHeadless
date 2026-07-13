import Foundation

public enum CLIStateRequirement: Equatable {
    case any
    case normalOnly
    case normalOrRecovery
    case restoreOnly
}

public enum CLIStateGate {
    public static func validate(
        state: RuntimeState,
        requirement: CLIStateRequirement,
        operation: String
    ) throws {
        let allowed: Bool
        switch requirement {
        case .any:
            allowed = true
        case .normalOnly:
            allowed = state.mode == .normal
        case .normalOrRecovery:
            allowed = state.mode == .normal || state.mode == .error || state.mode == .recoveryRequired
        case .restoreOnly:
            allowed = state.mode == .restoring || state.phase == .restorePaused
        }
        guard allowed else {
            throw CodexHeadlessError.invalidMode(current: state.mode, requestedOperation: operation)
        }
    }
}
