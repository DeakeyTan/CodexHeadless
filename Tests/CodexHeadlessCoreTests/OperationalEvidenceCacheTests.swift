import XCTest
@testable import CodexHeadlessCore

final class OperationalEvidenceCacheTests: XCTestCase {
    func testFiveMinutesOfRefreshesRemainFreshWithoutCleanNormal() {
        let cache = OperationalEvidenceCache()
        let start = Date(timeIntervalSince1970: 100)
        for second in stride(from: 0, through: 300, by: 10) {
            XCTAssertTrue(cache.beginRefresh())
            cache.complete(evidence(at: start.addingTimeInterval(Double(second))), at: start.addingTimeInterval(Double(second)))
            guard case .fresh = cache.availability(now: start.addingTimeInterval(Double(second + 5)), maximumAge: 15) else { return XCTFail("not fresh") }
        }
    }
    func testRefreshingRetainsRecentEvidenceAndStaleIsExplicit() {
        let cache = OperationalEvidenceCache(); let date = Date(timeIntervalSince1970: 10)
        cache.complete(evidence(at: date), at: date); XCTAssertTrue(cache.beginRefresh())
        guard case .refreshing(let previous?) = cache.availability(now: date.addingTimeInterval(2), maximumAge: 15) else { return XCTFail() }
        XCTAssertEqual(previous.capturedAt, date)
        cache.failRefresh("failed")
        guard case .stale = cache.availability(now: date.addingTimeInterval(20), maximumAge: 15) else { return XCTFail() }
    }
    func testConcurrentRefreshReservationHasSingleWinner() {
        let cache = OperationalEvidenceCache()
        let queue = DispatchQueue(label: "operational-cache-test", attributes: .concurrent)
        let group = DispatchGroup()
        let resultLock = NSLock()
        var winners = 0
        for _ in 0..<64 {
            group.enter()
            queue.async {
                if cache.beginRefresh() {
                    resultLock.lock(); winners += 1; resultLock.unlock()
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(winners, 1)
    }
    func testModeAndOperationMismatchCannotProveHealth() {
        let cache = OperationalEvidenceCache()
        let date = Date(timeIntervalSince1970: 10)
        cache.complete(evidence(at: date), at: date)
        guard case .fresh = cache.availability(now: date, maximumAge: 15, runtimeMode: .headless, operationID: "op") else {
            return XCTFail("matching evidence should be fresh")
        }
        guard case .unavailable = cache.availability(now: date, maximumAge: 15, runtimeMode: .confirmRequired, operationID: "op") else {
            return XCTFail("mode mismatch must be unavailable")
        }
        guard case .unavailable = cache.availability(now: date, maximumAge: 15, runtimeMode: .headless, operationID: "other") else {
            return XCTFail("operation mismatch must be unavailable")
        }
        XCTAssertTrue(cache.beginRefresh())
        guard case .refreshing(lastCompleted: nil) = cache.availability(now: date, maximumAge: 15, runtimeMode: .headless, operationID: "other") else {
            return XCTFail("incompatible history must not be shown during refresh")
        }
    }
    private func evidence(at date: Date) -> OperationalEvidence {
        .init(capturedAt: date, source: .periodicReconcile, runtimeMode: .headless, operationID: "op", phase: .headlessActive,
              runtimeReadStatus: .success, journal: .activeConsistent(operationID: "op", stage: .headless), processSnapshot: .success(durationMilliseconds: 1), keepAwake: .none, virtualDisplay: .none,
              display: .init(expectedManagedDisplayID: nil, observedManagedDisplayID: nil, managedDisplayEnumerated: false, expectedDisplayMatchesObserved: nil, physicalMainDisplayID: 1, builtInPresent: false), violations: [])
    }
}
