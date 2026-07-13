import XCTest
@testable import CodexHeadlessCore

final class RestoreReentryTests: XCTestCase {
    func testRestartSkipsVerifiedVirtualAndKeepAwakeCleanupStages() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        var state = RuntimeState.default
        state.mode = .restoring
        state.keepAwake = true
        state.virtualDisplayCreated = true
        try harness.stateStore.write(state)
        _ = try harness.recoveryJournalStore.create(operationID: "reentry")
        try harness.recoveryJournalStore.update {
            $0.stage = .cleanupInProgress
            $0.cleanupProgress.physicalTakeoverVerified = true
            $0.cleanupProgress.brightnessRestore = .skippedNotRequired
            $0.cleanupProgress.brightnessVerification = .skippedNotRequired
            $0.cleanupProgress.virtualHostStop = .completed
            $0.cleanupProgress.virtualDisplayDisappearance = .completed
            $0.cleanupProgress.keepAwakeHolderStop = .completed
            $0.cleanupProgress.keepAwakeAssertionDisappearance = .completed
            $0.cleanupProgress.touchBarRestore = .completed
        }

        let result = harness.controller.restoreNormal()
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(harness.virtual.destroyCallCount, 0)
        XCTAssertEqual(harness.sleep.disableCallCount, 0)
        XCTAssertEqual(harness.touchBar.showCallCount, 0)
    }

    func testFinalJournalFailureNeverReturnsCompleted() throws {
        let progress = RestoreCleanupProgress()
        let result = RestoreResult.cleanupIncomplete(progress: progress, reason: "journal finalization failed")
        XCTAssertFalse(result.succeeded)
    }
}
