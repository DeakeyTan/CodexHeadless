import XCTest
@testable import CodexHeadlessCore

final class ConfigurationMutationObservationTests: XCTestCase {
    func testFailedSnapshotRefusesMutation() throws {
        let setup = try makeGuard(snapshot: .failed("timeout"))
        XCTAssertThrowsError(try setup.guardUnderTest.acquire())
    }

    func testManagedHelperInSnapshotRefusesMutation() throws {
        let snapshot = ManagedProcessSnapshot(
            capturedAt: Date(),
            entries: [.init(pid: 42, command: "codex-headless internal-helper keep-awake-host")],
            succeeded: true, error: nil, durationMilliseconds: 1
        )
        let setup = try makeGuard(snapshot: snapshot)
        XCTAssertThrowsError(try setup.guardUnderTest.acquire())
    }

    func testSuccessfulEmptySnapshotAllowsCleanMutation() throws {
        let snapshot = ManagedProcessSnapshot(capturedAt: Date(), entries: [], succeeded: true, error: nil, durationMilliseconds: 1)
        let setup = try makeGuard(snapshot: snapshot)
        let lease = try setup.guardUnderTest.acquire()
        lease.release()
    }

    func testHelperTextInsideUnrelatedCommandDoesNotBlockMutation() throws {
        let snapshot = ManagedProcessSnapshot(
            capturedAt: Date(),
            entries: [
                .init(
                    pid: 43,
                    command: "rg internal-helper keep-awake-host /tmp/CodexHeadless.log"
                )
            ],
            succeeded: true,
            error: nil,
            durationMilliseconds: 1
        )
        let setup = try makeGuard(snapshot: snapshot)
        let lease = try setup.guardUnderTest.acquire()
        lease.release()
    }

    private func makeGuard(snapshot: ManagedProcessSnapshot) throws -> (guardUnderTest: ConfigurationMutationGuard, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = StateStore(stateFile: directory.appendingPathComponent("state.json"), lockFile: directory.appendingPathComponent("state.lock"))
        try state.write(.default)
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        let guardUnderTest = ConfigurationMutationGuard(
            stateStore: state,
            recoveryJournalStore: journal,
            displayManager: FakeDisplayManager(displays: [makeDisplay(id: 1, builtIn: true, main: true)]),
            operationLock: FakeWorkflowOperationLock(),
            snapshotProvider: CountingSnapshotProvider(snapshot: snapshot)
        )
        return (guardUnderTest, directory)
    }
}
