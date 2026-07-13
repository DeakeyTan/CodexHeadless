import XCTest
@testable import CodexHeadlessCore

final class ManagedProcessSnapshotTests: XCTestCase {
    func testSnapshotLoggingHonorsDiagnosticPolicy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("snapshot.log")
        let policy = DiagnosticLoggingPolicy(enabled: false)
        let provider = ManagedProcessSnapshotProvider(logger: CHLogger(logFile: log, policy: policy))
        XCTAssertTrue(provider.capture().succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
        policy.setEnabled(true)
        XCTAssertTrue(provider.capture().succeeded)
        XCTAssertTrue((try String(contentsOf: log, encoding: .utf8)).contains("process-snapshot"))
    }
    func testAssessmentCapturesOneSnapshotSharedByBothManagers() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        let provider = CountingSnapshotProvider(snapshot: .init(
            capturedAt: Date(), entries: [], succeeded: true, error: nil, durationMilliseconds: 1
        ))
        _ = CleanNormalAssessor(
            stateStore: harness.stateStore,
            recoveryJournalStore: harness.recoveryJournalStore,
            sleepManager: harness.sleep,
            virtualDisplayManager: harness.virtual,
            displayManager: harness.displays,
            snapshotProvider: provider
        ).assess()
        XCTAssertEqual(provider.captureCount, 1)
        XCTAssertEqual(harness.sleep.receivedSnapshots.count, 1)
        XCTAssertEqual(harness.virtual.receivedSnapshots.count, 1)
    }

    func testSnapshotFailureIsUnknownNotNone() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = StateStore(stateFile: directory.appendingPathComponent("state.json"), lockFile: directory.appendingPathComponent("state.lock"))
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        try state.write(.default)
        let failed = ManagedProcessSnapshot.failed("timeout")
        let sleep = SleepManager(stateStore: state, recoveryJournalStore: journal, snapshotProvider: CountingSnapshotProvider(snapshot: failed))
        XCTAssertEqual(sleep.managedResourceObservation(snapshot: failed).status, .unknown)
    }
}

final class CountingSnapshotProvider: ManagedProcessSnapshotProviding {
    var captureCount = 0
    let snapshot: ManagedProcessSnapshot
    init(snapshot: ManagedProcessSnapshot) { self.snapshot = snapshot }
    func capture() -> ManagedProcessSnapshot { captureCount += 1; return snapshot }
}
