import XCTest
@testable import CodexHeadlessCore

final class AppResponsivenessTests: XCTestCase {
    func testCachedAssessmentIsUnavailableWhileRefreshingOrStale() {
        let cache = CleanNormalAssessmentCache()
        XCTAssertTrue(cache.beginRefresh())
        XCTAssertNil(cache.snapshot().usableAssessment(now: Date(), maximumAge: 30))
        cache.complete(cleanAssessment(), at: Date(timeIntervalSince1970: 10))
        XCTAssertNotNil(cache.snapshot().usableAssessment(now: Date(timeIntervalSince1970: 20), maximumAge: 30))
        XCTAssertNil(cache.snapshot().usableAssessment(now: Date(timeIntervalSince1970: 50), maximumAge: 30))
    }

    func testRefreshRequestsCoalesce() {
        let cache = CleanNormalAssessmentCache()
        XCTAssertTrue(cache.beginRefresh())
        XCTAssertFalse(cache.beginRefresh())
        cache.complete(cleanAssessment())
        XCTAssertTrue(cache.beginRefresh())
    }

    func testRefreshRetainsPreviousAssessmentForTransitionComparison() {
        let cache = CleanNormalAssessmentCache()
        let previous = cleanAssessment()
        cache.complete(previous)
        XCTAssertTrue(cache.beginRefresh())
        XCTAssertEqual(cache.snapshot().assessment, previous)
        XCTAssertNil(cache.snapshot().usableAssessment(now: Date(), maximumAge: 30))

        var changed = cleanAssessment()
        changed.physicalDisplayTemporarilyUnavailable = true
        XCTAssertEqual(cache.complete(changed), previous)
    }

    func testFailedRefreshPreservesHistoryButStopsActionUseUntilFreshnessAllows() {
        let cache = CleanNormalAssessmentCache()
        let previous = cleanAssessment()
        cache.complete(previous, at: Date(timeIntervalSince1970: 10))
        XCTAssertTrue(cache.beginRefresh())
        cache.failRefresh()
        XCTAssertEqual(cache.snapshot().assessment, previous)
        XCTAssertNil(cache.snapshot().usableAssessment(now: Date(timeIntervalSince1970: 100), maximumAge: 30))
    }

    private func cleanAssessment() -> CleanNormalAssessment {
        CleanNormalAssessment(
            runtimeViolations: [], journalViolation: nil, observedResourceViolations: [],
            displayViolations: [], keepAwakeObservation: .none, virtualDisplayObservation: .none
        )
    }
}
