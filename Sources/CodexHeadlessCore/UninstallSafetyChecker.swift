import Foundation

public enum UninstallSafetyStatus: Equatable {
    case safe
    case refused
    case unverified
}

public struct UninstallSafetyResult: Equatable {
    public var status: UninstallSafetyStatus
    public var mode: HeadlessMode?
    public var classification: CleanNormalClassification?
    public var reason: String?

    public var exitCode: Int32 {
        switch status {
        case .safe: return CLIExitCode.success
        case .refused: return CLIExitCode.safetyRefusal
        case .unverified: return CLIExitCode.failure
        }
    }

    public var text: String {
        switch status {
        case .safe:
            return """
            Uninstall check: SAFE
            Mode: Normal
            Safety Classification: clean
            Recovery Journal: none
            Managed Resources: none
            """
        case .refused:
            return """
            Uninstall check: REFUSED
            Mode: \(mode?.rawValue ?? "Unknown")
            Safety Classification: \(classification?.rawValue ?? "unsafe")
            Required action: Restore to verified Clean Normal before uninstalling.
            \(reason.map { "Reason: \($0)" } ?? "")
            """
        case .unverified:
            return """
            Uninstall check: UNVERIFIED
            Reason: \(reason ?? "Required safety evidence could not be collected.")
            Required action: preserve the App and CLI and run Doctor.
            """
        }
    }
}

public final class UninstallSafetyChecker {
    private let stateStore: RuntimeStateStoring
    private let recoveryJournalStore: RecoveryJournalStoring
    private let assessor: CleanNormalAssessing
    private let operationLock: WorkflowOperationLocking

    public init(
        stateStore: RuntimeStateStoring,
        recoveryJournalStore: RecoveryJournalStoring,
        assessor: CleanNormalAssessing,
        operationLock: WorkflowOperationLocking = WorkflowOperationLock()
    ) {
        self.stateStore = stateStore
        self.recoveryJournalStore = recoveryJournalStore
        self.assessor = assessor
        self.operationLock = operationLock
    }

    public func check() -> UninstallSafetyResult {
        let lease: WorkflowOperationLeaseHandling
        do {
            lease = try operationLock.acquire(name: "uninstall-check")
        } catch {
            return .init(status: .unverified, mode: nil, classification: nil, reason: "Workflow coordination failed: \(error.localizedDescription)")
        }
        defer { lease.release() }

        return checkWhileLockHeld()
    }

    public func checkWhileLockHeld() -> UninstallSafetyResult {
        let state: RuntimeState
        do {
            state = try stateStore.read()
        } catch {
            return .init(status: .unverified, mode: nil, classification: nil, reason: "RuntimeState could not be read: \(error.localizedDescription)")
        }

        do {
            if try recoveryJournalStore.read() != nil {
                return .init(status: .refused, mode: state.mode, classification: .recoveryRequired, reason: "Recovery Journal is active.")
            }
        } catch {
            return .init(status: .unverified, mode: state.mode, classification: nil, reason: "Recovery Journal could not be read: \(error.localizedDescription)")
        }

        let assessment = assessor.assess()
        if !assessment.runtimeReadSucceeded || !assessment.journalReadSucceeded || !assessment.processSnapshotSucceeded
            || assessment.keepAwakeObservation.status == .unknown
            || assessment.virtualDisplayObservation.status == .unknown {
            return .init(
                status: .unverified,
                mode: state.mode,
                classification: assessment.classification,
                reason: assessment.violations.joined(separator: " ").nilIfEmpty ?? assessment.processSnapshotError
            )
        }
        guard state.mode == .normal, assessment.isClean else {
            return .init(
                status: .refused,
                mode: state.mode,
                classification: assessment.classification,
                reason: assessment.violations.joined(separator: " ").nilIfEmpty
            )
        }
        return .init(status: .safe, mode: .normal, classification: .clean, reason: nil)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
