import XCTest
@testable import CodexHeadlessCore

final class SleepManagerTests: XCTestCase {
    func testOwnershipMismatchDoesNotWriteOff() throws {
        let harness = try SleepHarness()
        harness.inspector.matchesResult = false
        harness.inspector.runningResult = true
        let result = harness.manager.disableKeepAwake()
        guard case .ownershipMismatch = result else { return XCTFail("Unexpected result: \(result)") }
        XCTAssertTrue(try harness.stateStore.read().keepAwake)
    }

    func testMatchingProcessCanStopAndWriteOff() throws {
        let harness = try SleepHarness()
        harness.inspector.matchesResult = true
        harness.inspector.terminateResult = .stopped
        let result = harness.manager.disableKeepAwake()
        XCTAssertTrue(result.completed)
        let state = try harness.stateStore.read()
        XCTAssertFalse(state.keepAwake)
        XCTAssertNil(state.keepAwakeHost)
    }

    func testLegacyNativeOwnerIsNeverReportedOff() throws {
        let harness = try SleepHarness()
        try harness.stateStore.transaction {
            $0.keepAwakeBackend = KeepAwakeBackend.native.rawValue
            $0.keepAwakeHost?.backend = .native
        }
        guard case .ownershipMismatch = harness.manager.disableKeepAwake() else {
            return XCTFail("Native owner must remain pending")
        }
        XCTAssertTrue(try harness.stateStore.read().keepAwake)
    }
}

private final class SleepHarness {
    let directory: URL
    let stateStore: StateStore
    let journalStore: RecoveryJournalStore
    let inspector = FakeManagedProcessInspector()
    let manager: SleepManager

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SleepManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateStore = StateStore(stateFile: directory.appendingPathComponent("state.json"), lockFile: directory.appendingPathComponent("state.lock"))
        journalStore = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        let ownership = ManagedProcessOwnershipRecord(
            instanceID: "keep-1", pid: 42, executableCanonicalPath: "/bin/sh",
            processStartTime: "start-1", expectedCommandFragments: ["codexheadless-keepawake-keep-1"],
            ownerOperationID: "operation-1", resourceKind: "keep-awake", createdAt: Date()
        )
        let record = KeepAwakeHostRecord(
            instanceID: "keep-1", pid: 42, backend: .caffeinate, executablePath: "/bin/sh",
            startedAt: Date(), ownerProcessKind: "test", ownership: ownership
        )
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.keepAwakeBackend = KeepAwakeBackend.caffeinate.rawValue
        state.caffeinatePID = 42
        state.keepAwakeHost = record
        try stateStore.write(state)
        _ = try journalStore.create(operationID: "operation-1")
        try journalStore.update {
            $0.keepAwakeHost = record
            $0.keepAwakeResource = ManagedResourceJournalRecord(
                instanceID: "keep-1", resourceKind: "keep-awake", operationID: "operation-1",
                stage: .committed, ownership: ownership
            )
        }
        let configFile = directory.appendingPathComponent("config.json")
        let config = ConfigManager(configFile: configFile, lockFile: directory.appendingPathComponent("config.lock"), healthFile: directory.appendingPathComponent("health.json"))
        try config.save(.default)
        manager = SleepManager(
            stateStore: stateStore,
            configManager: config,
            processInspector: inspector,
            recoveryJournalStore: journalStore
        )
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

private final class FakeManagedProcessInspector: ManagedProcessInspecting {
    var matchesResult = true
    var runningResult = true
    var terminateResult: ManagedResourceCleanupResult = .stopped
    func isRunning(pid: Int32) -> Bool { runningResult }
    func command(pid: Int32) -> String? { runningResult ? "/bin/sh codexheadless-keepawake-keep-1" : nil }
    func matches(_ identity: ManagedProcessIdentity) -> Bool { matchesResult }
    func terminate(_ identity: ManagedProcessIdentity, timeoutSeconds: TimeInterval) -> ManagedResourceCleanupResult {
        guard matchesResult else { return .ownershipMismatch(reason: "fake ownership mismatch") }
        matchesResult = false
        runningResult = false
        return terminateResult
    }
}
