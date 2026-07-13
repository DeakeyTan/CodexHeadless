import XCTest
@testable import CodexHeadlessCore

final class CleanNormalInvariantTests: XCTestCase {
    func testEveryRuntimeResourceViolationRejectsCleanNormal() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        let mutations: [(inout RuntimeState) -> Void] = [
            { $0.keepAwake = true },
            { $0.caffeinatePID = 7 },
            { $0.virtualDisplayCreated = true },
            { $0.virtualDisplayID = 9 },
            { $0.builtInSoftDisconnected = true },
            { $0.builtInBrightnessDimmed = true },
            { $0.touchBarHidden = true }
        ]
        for mutate in mutations {
            var state = RuntimeState.default
            mutate(&state)
            try harness.stateStore.write(state)
            XCTAssertFalse(harness.controller.assessCleanNormal().isClean)
        }
    }

    func testPossibleObservedOwnerRejectsEnableWithoutStartingResources() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        harness.sleep.observation = .init(status: .possibleOwned, summary: "possible orphan", pid: 44)
        XCTAssertThrowsError(try harness.controller.enableHeadless())
        XCTAssertEqual(harness.sleep.enableCallCount, 0)
        XCTAssertEqual(harness.virtual.createCallCount, 0)
    }
}
