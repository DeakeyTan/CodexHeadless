import XCTest
@testable import CodexHeadlessCore

final class StandaloneJournalLifecycleTests: XCTestCase {
    func testFinalResourceCleanupDeletesStandaloneJournal() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        _ = try harness.recoveryJournalStore.create(operationID: "standalone-test")
        try harness.recoveryJournalStore.update {
            $0.keepAwakeResource = .init(instanceID: "keep", resourceKind: "keep-awake", operationID: "standalone-test", stage: .cleaned)
            $0.virtualDisplayResource = .init(instanceID: "virtual", resourceKind: "virtual-display", operationID: "standalone-test", stage: .cleaned)
        }
        try StandaloneJournalFinalizer(
            stateStore: harness.stateStore,
            journalStore: harness.recoveryJournalStore,
            snapshotProvider: CountingSnapshotProvider(snapshot: emptySnapshot())
        ).finalizeIfClean()
        XCTAssertNil(try harness.recoveryJournalStore.read())
    }

    func testActiveSecondResourcePreservesJournal() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        _ = try harness.recoveryJournalStore.create(operationID: "standalone-test")
        try harness.recoveryJournalStore.update {
            $0.keepAwakeResource = .init(instanceID: "keep", resourceKind: "keep-awake", operationID: "standalone-test", stage: .cleaned)
            $0.virtualDisplayResource = .init(instanceID: "virtual", resourceKind: "virtual-display", operationID: "standalone-test", stage: .committed)
        }
        try StandaloneJournalFinalizer(
            stateStore: harness.stateStore,
            journalStore: harness.recoveryJournalStore,
            snapshotProvider: CountingSnapshotProvider(snapshot: emptySnapshot())
        ).finalizeIfClean()
        XCTAssertNotNil(try harness.recoveryJournalStore.read())
    }

    private func emptySnapshot() -> ManagedProcessSnapshot {
        .init(capturedAt: Date(), entries: [], succeeded: true, error: nil, durationMilliseconds: 1)
    }
}
