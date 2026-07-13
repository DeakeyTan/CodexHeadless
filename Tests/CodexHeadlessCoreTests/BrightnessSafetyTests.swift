import XCTest
@testable import CodexHeadlessCore

final class BrightnessSafetyTests: XCTestCase {
    func testUnknownOriginalBrightnessRejectsBeforeAnySideEffect() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        harness.builtIn.brightness = nil
        XCTAssertThrowsError(try harness.controller.enableHeadless())
        XCTAssertEqual(harness.sleep.enableCallCount, 0)
        XCTAssertEqual(harness.virtual.createCallCount, 0)
        XCTAssertEqual(harness.builtIn.dimCallCount, 0)
        XCTAssertNil(try harness.recoveryJournalStore.read())
    }

    func testBrightnessRestoreFailurePreservesReplacementAndKeepAwake() throws {
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 1, builtIn: true, main: true),
            makeDisplay(id: 9, builtIn: false, managed: true, main: false)
        ])
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.virtualDisplayCreated = true
        state.virtualDisplayID = 9
        state.builtInBrightnessDimmed = true
        state.originalBrightness = 0.63
        try harness.stateStore.write(state)
        _ = try harness.recoveryJournalStore.create(operationID: "brightness-restore")
        harness.builtIn.restoreBrightnessResult = .failed("readback mismatch")

        let result = harness.controller.restoreNormal()
        guard case .cleanupIncomplete = result else { return XCTFail("expected cleanupIncomplete") }
        XCTAssertEqual(harness.virtual.destroyCallCount, 0)
        XCTAssertEqual(harness.sleep.disableCallCount, 0)
        XCTAssertEqual(try harness.stateStore.read().mode, .restoring)
        XCTAssertNotNil(try harness.recoveryJournalStore.read())
    }
}
