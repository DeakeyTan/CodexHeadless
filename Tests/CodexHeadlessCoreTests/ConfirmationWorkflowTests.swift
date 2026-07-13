import XCTest
@testable import CodexHeadlessCore

final class ConfirmationWorkflowTests: XCTestCase {
    func testConfirmAtomicallyEntersHeadless() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 9, builtIn: false, managed: true, main: true)])
        var state = RuntimeState.default
        state.mode = .confirmRequired
        state.phase = .waitingForConfirmation
        state.confirmationRequired = true
        state.rollbackConfirmed = false
        state.rollbackDeadline = Date().addingTimeInterval(30)
        try harness.stateStore.write(state)

        XCTAssertTrue(harness.controller.confirm())

        let confirmed = try harness.stateStore.read()
        XCTAssertEqual(confirmed.mode, .headless)
        XCTAssertEqual(confirmed.phase, .headlessActive)
        XCTAssertTrue(confirmed.rollbackConfirmed)
        XCTAssertNil(confirmed.rollbackDeadline)
        XCTAssertEqual(harness.operationLock.acquisitions, ["confirm"])
    }

    func testConfirmRereadsStateAfterLockAndCannotOverwriteRestore() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        var state = RuntimeState.default
        state.mode = .confirmRequired
        state.phase = .waitingForConfirmation
        try harness.stateStore.write(state)
        harness.operationLock.onAcquire = { [weak harness] name in
            guard name == "confirm", let harness else { return }
            try? harness.stateStore.transaction { state in
                state.mode = .normal
                state.phase = .idle
            }
        }

        XCTAssertFalse(harness.controller.confirm())
        XCTAssertEqual(try harness.stateStore.read().mode, .normal)
    }

    func testExpiredRollbackUsesSingleLockedRestoreWorkflow() throws {
        var config = AppConfig.default
        var timing = TimingConfig.default
        timing.restorePhysicalDisplayWaitSeconds = 0
        timing.restorePhysicalDisplayGraceSeconds = 0
        timing.restorePostPromoteStabilizationMilliseconds = 0
        config.timing = timing
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 2, builtIn: false, main: false),
            makeDisplay(id: 9, builtIn: false, managed: true, main: true)
        ], config: config)
        var state = RuntimeState.default
        state.mode = .confirmRequired
        state.phase = .waitingForConfirmation
        state.keepAwake = true
        state.virtualDisplayCreated = true
        state.virtualDisplayID = 9
        state.rollbackConfirmed = false
        state.rollbackDeadline = Date().addingTimeInterval(-1)
        try harness.stateStore.write(state)
        try harness.seedRecoveryJournal(for: state)

        harness.controller.rollbackIfNeeded()

        XCTAssertEqual(try harness.stateStore.read().mode, .normal)
        XCTAssertEqual(harness.operationLock.acquisitions, ["rollback"])
        XCTAssertEqual(harness.virtual.destroyCallCount, 1)
    }
}
