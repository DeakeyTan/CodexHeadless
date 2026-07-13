import Foundation

public enum CodexHeadlessError: LocalizedError, Equatable {
    case configurationRecoveryRequired
    case runtimeStateRecoveryRequired
    case restoreCooldown(secondsRemaining: Int)
    case virtualDisplayUnavailable(message: String)
    case displayHandoffFailed(message: String)
    case enableCancelled(message: String)
    case keepAwakeInvariant(message: String)
    case managedResource(message: String)
    case invalidConfiguration(message: String)
    case displayOperation(message: String)
    case displayLayout(message: String)
    case virtualDisplayOperation(message: String)
    case invalidMode(current: HeadlessMode, requestedOperation: String)
    case recoveryJournalUnavailable(message: String)
    case recoveryJournalDamaged(message: String)
    case resourceDrift(message: String)
    case cleanupIncomplete(message: String)
    case keepAwakeOwnership(message: String)
    case virtualDisplayOwnership(message: String)
    case brightnessCapabilityUnavailable(message: String)

    public var errorDescription: String? {
        switch self {
        case .configurationRecoveryRequired:
            return "Configuration is damaged. Reset to Safe Defaults or repair config.json before enabling Headless Mode."
        case .runtimeStateRecoveryRequired:
            return "Runtime state is damaged or unknown. Run `codex-headless off` before enabling Headless Mode."
        case .restoreCooldown(let secondsRemaining):
            return "Normal Mode was just restored. Please wait \(secondsRemaining) seconds before enabling Headless Mode again."
        case .virtualDisplayUnavailable(let message),
             .displayHandoffFailed(let message),
             .enableCancelled(let message),
             .keepAwakeInvariant(let message),
             .managedResource(let message),
             .invalidConfiguration(let message),
             .displayOperation(let message),
             .displayLayout(let message),
             .virtualDisplayOperation(let message),
             .recoveryJournalUnavailable(let message),
             .recoveryJournalDamaged(let message),
             .resourceDrift(let message),
             .cleanupIncomplete(let message),
             .keepAwakeOwnership(let message),
             .virtualDisplayOwnership(let message),
             .brightnessCapabilityUnavailable(let message):
            return message
        case .invalidMode(let current, let operation):
            return "Cannot \(operation) while mode is \(current.rawValue). Restore Normal Mode first."
        }
    }

}
