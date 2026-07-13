import XCTest
@testable import CodexHeadlessCore

final class ManagedResourceCommitTests: XCTestCase {
    func testKeepAwakeAfterRuntimeCommitCompensatesStateBeforeClearingJournalOwner() throws {
        let setup = try committedKeepAwakeManager(failCompensation: false)
        try setup.manager.compensateFailedStart(record: setup.record, runtimeCommitted: true, cleanup: .stopped)
        XCTAssertFalse(try setup.state.read().keepAwake)
        XCTAssertNil(try setup.journal.read()?.keepAwakeHost)
        XCTAssertEqual(try setup.journal.read()?.keepAwakeResource?.stage, .cleaned)
    }

    func testKeepAwakeCompensationFailureRetainsJournalOwner() throws {
        let setup = try committedKeepAwakeManager(failCompensation: true)
        XCTAssertThrowsError(try setup.manager.compensateFailedStart(record: setup.record, runtimeCommitted: true, cleanup: .stopped))
        XCTAssertNotNil(try setup.journal.read()?.keepAwakeHost)
        XCTAssertEqual(try setup.journal.read()?.keepAwakeResource?.stage, .cleanupPending)
    }

    func testVirtualAfterRuntimeCommitCompensatesStateBeforeClearingJournalOwner() throws {
        let setup = try committedVirtualManager(failCompensation: false)
        try setup.manager.compensateFailedStart(record: setup.record, runtimeCommitted: true, cleanup: .stopped, displayDisappeared: true)
        XCTAssertFalse(try setup.state.read().virtualDisplayCreated)
        XCTAssertNil(try setup.journal.read()?.virtualDisplayHost)
        XCTAssertEqual(try setup.journal.read()?.virtualDisplayResource?.stage, .cleaned)
    }

    func testVirtualCompensationFailureRetainsJournalOwner() throws {
        let setup = try committedVirtualManager(failCompensation: true)
        XCTAssertThrowsError(try setup.manager.compensateFailedStart(record: setup.record, runtimeCommitted: true, cleanup: .stopped, displayDisappeared: true))
        XCTAssertNotNil(try setup.journal.read()?.virtualDisplayHost)
        XCTAssertEqual(try setup.journal.read()?.virtualDisplayResource?.stage, .cleanupPending)
    }

    private func committedVirtualManager(failCompensation: Bool) throws -> (
        manager: VirtualDisplayManager, state: FailingStateStore, journal: RecoveryJournalStore, record: VirtualDisplayHostRecord
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let record = VirtualDisplayHostRecord(instanceID: "virtual", pid: 43, executablePath: "/tmp/helper", startedAt: Date())
        var runtime = RuntimeState.default
        runtime.virtualDisplayCreated = true; runtime.virtualDisplayPID = 43; runtime.virtualDisplayID = 9; runtime.virtualDisplayHost = record
        let state = FailingStateStore(state: runtime)
        if failCompensation { state.shouldFailTransaction = { !$0.virtualDisplayCreated } }
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        _ = try journal.create(operationID: "operation")
        try journal.update {
            $0.virtualDisplayHost = record
            $0.virtualDisplayResource = .init(instanceID: "virtual", resourceKind: "virtual-display", operationID: "operation", stage: .committed, displayID: 9)
        }
        return (
            VirtualDisplayManager(stateStore: state, displayManager: FakeDisplayManager(displays: []), recoveryJournalStore: journal),
            state, journal, record
        )
    }

    private func committedKeepAwakeManager(failCompensation: Bool) throws -> (
        manager: SleepManager, state: FailingStateStore, journal: RecoveryJournalStore, record: KeepAwakeHostRecord
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let record = KeepAwakeHostRecord(instanceID: "holder", pid: 42, backend: .caffeinate, executablePath: "/tmp/helper", startedAt: Date(), ownerProcessKind: "test")
        var runtime = RuntimeState.default
        runtime.keepAwake = true; runtime.caffeinatePID = 42; runtime.keepAwakeHost = record
        let state = FailingStateStore(state: runtime)
        if failCompensation { state.shouldFailTransaction = { !$0.keepAwake } }
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        _ = try journal.create(operationID: "operation")
        try journal.update {
            $0.keepAwakeHost = record
            $0.keepAwakeResource = .init(instanceID: "holder", resourceKind: "keep-awake", operationID: "operation", stage: .committed)
        }
        return (SleepManager(stateStore: state, recoveryJournalStore: journal), state, journal, record)
    }

    func testNormalRuntimeDoesNotDeleteJournalBeforeCompensatingStartedResource() throws {
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 1, builtIn: true, main: true)
        ])
        _ = try harness.recoveryJournalStore.create(operationID: "runtime-commit-failed")
        try harness.recoveryJournalStore.update {
            $0.keepAwakeResource = ManagedResourceJournalRecord(
                instanceID: "holder", resourceKind: "keep-awake",
                operationID: "runtime-commit-failed", stage: .started
            )
        }
        var execution = EnableExecutionContext()
        execution.journalCreated = true
        execution.keepAwakeStarted = true

        try harness.controller.compensateEnableFailure(execution, cause: FakeError.requested)

        XCTAssertEqual(harness.sleep.disableCallCount, 1)
        XCTAssertNil(try harness.recoveryJournalStore.read())
        XCTAssertEqual(try harness.stateStore.read().mode, .normal)
    }

    func testCleanupFailureRetainsJournalAndNonNormalStateForRetry() throws {
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 1, builtIn: true, main: true),
            makeDisplay(id: 9, builtIn: false, managed: true, main: false)
        ])
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.virtualDisplayCreated = true
        state.virtualDisplayID = 9
        state.builtInSoftDisconnected = true
        try harness.stateStore.write(state)
        _ = try harness.recoveryJournalStore.create(operationID: "commit-window")
        harness.virtual.destroyResult = .failed(reason: "terminate failed; resource still observed")

        let first = harness.controller.restoreNormal()
        guard case .cleanupIncomplete = first else { return XCTFail("expected cleanupIncomplete") }
        XCTAssertNotNil(try harness.recoveryJournalStore.read())
        XCTAssertNotEqual(try harness.stateStore.read().mode, .normal)

        harness.virtual.destroyResult = .stopped
        harness.sleep.disableResult = .stopped
        let second = harness.controller.restoreNormal()
        XCTAssertTrue(second.succeeded)
        XCTAssertNil(try harness.recoveryJournalStore.read())
    }

    func testJournalResourceStageRepresentsIntentThroughCleanup() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        _ = try harness.recoveryJournalStore.create(operationID: "resource-stage")
        try harness.recoveryJournalStore.update {
            $0.keepAwakeResource = ManagedResourceJournalRecord(
                instanceID: "holder", resourceKind: "keep-awake", operationID: "resource-stage", stage: .intent
            )
        }
        XCTAssertEqual(try harness.recoveryJournalStore.read()?.keepAwakeResource?.stage, .intent)
        try harness.recoveryJournalStore.update { $0.keepAwakeResource?.stage = .cleanupPending }
        XCTAssertEqual(try harness.recoveryJournalStore.read()?.keepAwakeResource?.stage, .cleanupPending)
    }
}
