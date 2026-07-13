import XCTest
@testable import CodexHeadlessCore

final class RuntimeStateInvariantTests: XCTestCase {
    func testResetClearsEveryManagedResourceReference() {
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.caffeinatePID = 12
        state.keepAwakeBackend = KeepAwakeBackend.caffeinate.rawValue
        state.keepAwakeHost = KeepAwakeHostRecord(
            instanceID: "keep", pid: 12, backend: .caffeinate, executablePath: "/bin/sh",
            startedAt: Date(), ownerProcessKind: "test"
        )
        state.virtualDisplayCreated = true
        state.virtualDisplayID = 9
        state.virtualDisplayPID = 13
        state.virtualDisplayHost = VirtualDisplayHostRecord(instanceID: "virtual", pid: 13, executablePath: "/tmp/helper", startedAt: Date())
        state.replacementDisplayID = 9
        state.confirmationRequired = true

        HeadlessController.resetRuntimeState(&state, lastError: nil, cooldownUntil: nil)

        XCTAssertEqual(state.mode, .normal)
        XCTAssertFalse(state.keepAwake)
        XCTAssertNil(state.keepAwakeHost)
        XCTAssertNil(state.caffeinatePID)
        XCTAssertNil(state.keepAwakeBackend)
        XCTAssertFalse(state.virtualDisplayCreated)
        XCTAssertNil(state.virtualDisplayHost)
        XCTAssertNil(state.virtualDisplayID)
        XCTAssertNil(state.replacementDisplayID)
        XCTAssertFalse(state.confirmationRequired == true)
    }
}
