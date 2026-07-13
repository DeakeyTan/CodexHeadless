import Foundation

public struct CachedCleanNormalAssessment {
    public var assessment: CleanNormalAssessment?
    public var checkedAt: Date?
    public var isRefreshing: Bool

    public func usableAssessment(now: Date, maximumAge: TimeInterval) -> CleanNormalAssessment? {
        guard !isRefreshing, let assessment, let checkedAt,
              now.timeIntervalSince(checkedAt) <= maximumAge else { return nil }
        return assessment
    }
}

public final class CleanNormalAssessmentCache {
    private let lock = NSLock()
    private var value = CachedCleanNormalAssessment(assessment: nil, checkedAt: nil, isRefreshing: false)

    public init() {}

    public func snapshot() -> CachedCleanNormalAssessment {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    @discardableResult
    public func beginRefresh() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !value.isRefreshing else { return false }
        value.isRefreshing = true
        return true
    }

    @discardableResult
    public func complete(_ assessment: CleanNormalAssessment, at date: Date = Date()) -> CleanNormalAssessment? {
        lock.lock(); defer { lock.unlock() }
        let previous = value.assessment
        value = CachedCleanNormalAssessment(assessment: assessment, checkedAt: date, isRefreshing: false)
        return previous
    }

    public func failRefresh() {
        lock.lock(); defer { lock.unlock() }
        value.isRefreshing = false
    }

    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        value.assessment = nil
        value.checkedAt = nil
    }
}
