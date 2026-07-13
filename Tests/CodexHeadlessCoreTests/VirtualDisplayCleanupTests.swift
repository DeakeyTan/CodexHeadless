import XCTest
@testable import CodexHeadlessCore

final class VirtualDisplayCleanupTests: XCTestCase {
    func testMissingPIDButDisplayStillPresentIsDrift() throws {
        let harness = try VirtualCleanupHarness(displayPresent: true)
        guard case .failed(let reason) = harness.manager.destroyVirtualDisplayIfManaged() else {
            return XCTFail("Expected resource drift failure")
        }
        XCTAssertTrue(reason.contains("still enumerated"))
        XCTAssertTrue(try harness.stateStore.read().virtualDisplayCreated)
    }

    func testMissingPIDAndDisplayGoneCanClearState() throws {
        let harness = try VirtualCleanupHarness(displayPresent: false)
        XCTAssertTrue(harness.manager.destroyVirtualDisplayIfManaged().completed)
        XCTAssertFalse(try harness.stateStore.read().virtualDisplayCreated)
        XCTAssertNil(try harness.stateStore.read().virtualDisplayHost)
    }

    func testJournalInstanceMismatchPreservesState() throws {
        let harness = try VirtualCleanupHarness(displayPresent: false)
        try harness.journalStore.update { $0.virtualDisplayHost?.instanceID = "different" }
        guard case .ownershipMismatch = harness.manager.destroyVirtualDisplayIfManaged() else {
            return XCTFail("Expected ownership mismatch")
        }
        XCTAssertTrue(try harness.stateStore.read().virtualDisplayCreated)
    }
}

private final class VirtualCleanupHarness {
    let directory: URL
    let stateStore: StateStore
    let journalStore: RecoveryJournalStore
    let manager: VirtualDisplayManager

    init(displayPresent: Bool) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("VirtualCleanupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateStore = StateStore(stateFile: directory.appendingPathComponent("state.json"), lockFile: directory.appendingPathComponent("state.lock"))
        journalStore = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        let ownership = ManagedProcessOwnershipRecord(
            instanceID: "virtual-1", pid: 99, executableCanonicalPath: "/tmp/helper",
            processStartTime: "start", expectedCommandFragments: ["internal-helper", "virtual-display-host", "virtual-1"],
            ownerOperationID: "operation", resourceKind: "virtual-display", createdAt: Date()
        )
        let record = VirtualDisplayHostRecord(
            instanceID: "virtual-1", pid: 99, executablePath: "/tmp/helper", startedAt: Date(), ownership: ownership
        )
        var state = RuntimeState.default
        state.mode = .headless
        state.virtualDisplayCreated = true
        state.virtualDisplayPID = 99
        state.virtualDisplayID = 9
        state.virtualDisplayHost = record
        try stateStore.write(state)
        _ = try journalStore.create(operationID: "operation")
        try journalStore.update {
            $0.virtualDisplayHost = record
            $0.virtualDisplayResource = ManagedResourceJournalRecord(
                instanceID: "virtual-1", resourceKind: "virtual-display", operationID: "operation",
                stage: .committed, ownership: ownership, displayID: 9
            )
        }
        let displays = FakeDisplayManager(displays: displayPresent ? [makeDisplay(id: 9, builtIn: false, managed: true, main: true)] : [])
        manager = VirtualDisplayManager(
            stateStore: stateStore,
            displayManager: displays,
            processInspector: MissingProcessInspector(),
            recoveryJournalStore: journalStore,
            clock: FakeWorkflowClock()
        )
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

private final class MissingProcessInspector: ManagedProcessInspecting {
    func isRunning(pid: Int32) -> Bool { false }
    func command(pid: Int32) -> String? { nil }
    func matches(_ identity: ManagedProcessIdentity) -> Bool { false }
    func terminate(_ identity: ManagedProcessIdentity, timeoutSeconds: TimeInterval) -> ManagedResourceCleanupResult { .alreadyStopped }
}
