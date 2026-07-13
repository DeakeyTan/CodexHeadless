import XCTest
@testable import CodexHeadlessCore

final class TouchBarRestoreTests: XCTestCase {
    func testTouchBarFailurePreservesStateAndRetrySucceeds() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        var state = RuntimeState.default
        state.mode = .headless
        state.touchBarHidden = true
        try harness.stateStore.write(state)
        _ = try harness.recoveryJournalStore.create(operationID: "touchbar-restore")
        try harness.recoveryJournalStore.update { $0.stage = .headless }
        harness.touchBar.showResult = .failed("ControlStrip unavailable")

        let first = harness.controller.restoreNormal()
        guard case .cleanupIncomplete = first else { return XCTFail("expected cleanupIncomplete") }
        XCTAssertNotNil(try harness.recoveryJournalStore.read())
        XCTAssertTrue(try harness.stateStore.read().touchBarHidden == true)

        harness.touchBar.showResult = .succeeded(method: "fake", message: "restored")
        XCTAssertTrue(harness.controller.restoreNormal().succeeded)
        XCTAssertNil(try harness.recoveryJournalStore.read())
    }

    func testUnchangedTouchBarIsSkipped() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        XCTAssertEqual(harness.controller.restoreNormal(), .alreadyNormal)
        XCTAssertEqual(harness.touchBar.showCallCount, 0)
    }
}
