import XCTest
@testable import CodexHeadlessCore

final class RestoreSuccessGateTests: XCTestCase {
    func testCleanNoOpRestoreUsesFinalGate() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        XCTAssertEqual(harness.controller.restoreNormal(), .alreadyNormal)
    }

    func testPossibleOwnerPreventsNoOpSuccess() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        harness.sleep.observation = .init(status: .possibleOwned, summary: "possible helper", pid: 42)
        XCTAssertFalse(harness.controller.restoreNormal().succeeded)
    }

    func testFinalizingJournalIsDeletedBeforeSuccess() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        _ = try harness.recoveryJournalStore.create(operationID: "finalizing")
        try harness.recoveryJournalStore.update {
            $0.cleanupProgress.finalStatePersisted = true
            $0.stage = .finalStatePersisted
        }
        XCTAssertEqual(harness.controller.restoreNormal(), .alreadyNormal)
        XCTAssertNil(try harness.recoveryJournalStore.read())
    }
}
