import XCTest
@testable import CodexHeadlessCore

final class KeepAwakeInvariantTests: XCTestCase {
    func testHeadlessModeCannotDisableKeepAwakeIndependently() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 2, builtIn: false, main: true)])
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        try harness.stateStore.write(state)

        XCTAssertThrowsError(try harness.controller.setKeepAwake(false)) { error in
            guard case CodexHeadlessError.keepAwakeInvariant = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(harness.sleep.disableCallCount, 0)
    }

    func testNormalModeCanDisableKeepAwake() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        var state = RuntimeState.default
        state.keepAwake = true
        try harness.stateStore.write(state)

        try harness.controller.setKeepAwake(false)

        XCTAssertEqual(harness.sleep.disableCallCount, 1)
    }
}
