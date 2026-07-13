import Foundation

public enum OperationalTransitionDiagnostic {
    public static func message(previous: OperationalEvidence?, current: OperationalEvidence, previousPresentation: OperationalSafetyPresentation?, currentPresentation: OperationalSafetyPresentation) -> String? {
        guard !sameObservedFacts(previous, current) || previousPresentation != currentPresentation else { return nil }
        let from = previousPresentation?.title ?? "unavailable"
        let violations = String(current.violations.map(String.init(describing:)).joined(separator: "|").prefix(300))
        return "[Safety] operational \(from)->\(currentPresentation.title) source=\(current.source.rawValue) violations=\(violations.isEmpty ? "none" : violations)"
    }

    private static func sameObservedFacts(_ previous: OperationalEvidence?, _ current: OperationalEvidence) -> Bool {
        guard let previous else { return false }
        return previous.runtimeMode == current.runtimeMode
            && previous.operationID == current.operationID
            && previous.phase == current.phase
            && previous.runtimeReadStatus == current.runtimeReadStatus
            && previous.journal == current.journal
            && processOutcome(previous.processSnapshot) == processOutcome(current.processSnapshot)
            && previous.keepAwake == current.keepAwake
            && previous.virtualDisplay == current.virtualDisplay
            && previous.display == current.display
            && previous.violations == current.violations
    }

    private static func processOutcome(_ evidence: OperationalProcessSnapshotEvidence) -> String {
        switch evidence {
        case .success: return "success"
        case .failed(let reason): return "failed:\(reason)"
        }
    }
}
