import Foundation

public final class OperationalEvidenceCache {
    private let lock = NSLock()
    private var evidence: OperationalEvidence?
    private var checkedAt: Date?
    private var refreshing = false
    private var refreshError: String?
    public init() {}
    public func beginRefresh() -> Bool { lock.lock(); defer { lock.unlock() }; guard !refreshing else { return false }; refreshing = true; return true }
    @discardableResult public func complete(_ value: OperationalEvidence, at date: Date = Date()) -> OperationalEvidence? { lock.lock(); defer { lock.unlock() }; let old = evidence; evidence = value; checkedAt = date; refreshing = false; refreshError = nil; return old }
    public func failRefresh(_ error: String) { lock.lock(); defer { lock.unlock() }; refreshing = false; refreshError = error }
    public func clear() { lock.lock(); defer { lock.unlock() }; evidence = nil; checkedAt = nil; refreshing = false; refreshError = nil }
    public func availability(
        now: Date = Date(),
        maximumAge: TimeInterval,
        runtimeMode: HeadlessMode? = nil,
        operationID: String? = nil
    ) -> OperationalEvidenceAvailability {
        lock.lock(); defer { lock.unlock() }
        let compatible = evidence.flatMap { value -> OperationalEvidence? in
            if let runtimeMode, value.runtimeMode != runtimeMode { return nil }
            if let operationID, value.operationID != operationID { return nil }
            return value
        }
        if refreshing { return .refreshing(lastCompleted: compatible) }
        guard let evidence, let checkedAt else { return .unavailable(refreshError) }
        guard compatible != nil else { return .unavailable("Operational evidence belongs to a different workflow.") }
        if now.timeIntervalSince(checkedAt) > maximumAge { return .stale(evidence) }
        return .fresh(evidence)
    }
}
