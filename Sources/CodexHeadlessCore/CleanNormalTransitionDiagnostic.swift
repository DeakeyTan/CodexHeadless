import Foundation

public enum CleanNormalTransitionDiagnostic {
    public static func message(
        previous: CleanNormalAssessment?,
        current: CleanNormalAssessment,
        source: String,
        durationMilliseconds: UInt64
    ) -> String? {
        guard previous != current else { return nil }
        let previousName = previous?.classification.rawValue ?? "unavailable"
        return "[Safety] transition \(previousName)->\(current.classification.rawValue) source=\(safe(source)) runtime=\(list(current.runtimeViolations)) journal=\(safe(current.journalViolation ?? "none")) keepAwake=\(observation(current.keepAwakeObservation)) virtual=\(observation(current.virtualDisplayObservation)) display=\(list(current.displayViolations)) snapshot=\(current.processSnapshotSucceeded ? "success" : "failed:\(safe(current.processSnapshotError ?? "unknown"))") durationMs=\(durationMilliseconds)"
    }

    private static func observation(_ value: ManagedResourceObservation) -> String {
        "\(value.status.rawValue):pid=\(value.pid.map(String.init) ?? "none"):\(safe(value.summary))"
    }

    private static func list(_ values: [String]) -> String {
        values.isEmpty ? "[]" : "[\(values.map(safe).joined(separator: "|"))]"
    }

    private static func safe(_ value: String) -> String {
        String(value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .prefix(300))
    }
}
