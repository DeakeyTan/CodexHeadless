import XCTest
@testable import CodexHeadlessCore

final class InternalHelperAuthorizationTests: XCTestCase {
    func testCapabilityIsBoundAndOneTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex-headless")
        try Data("helper".utf8).write(to: executable)
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        _ = try journal.create(operationID: "operation")
        try journal.update { $0.stage = .handoffCommitted }
        let store = HelperCapabilityStore(directory: directory.appendingPathComponent("caps"), lockFile: directory.appendingPathComponent("caps.lock"), journalStore: journal)
        let capability = try store.reserve(
            kind: .touchBarApply, operationID: "operation", expectedParentPID: 123,
            expectedExecutablePath: executable.path
        )

        XCTAssertThrowsError(try store.consume(
            capabilityID: capability.capabilityID, nonce: "wrong", operationID: "operation",
            kind: .touchBarApply, actualParentPID: 123, actualExecutablePath: executable.path
        ))
        XCTAssertNoThrow(try store.consume(
            capabilityID: capability.capabilityID, nonce: capability.nonce, operationID: "operation",
            kind: .touchBarApply, actualParentPID: 123, actualExecutablePath: executable.path
        ))
        XCTAssertThrowsError(try store.consume(
            capabilityID: capability.capabilityID, nonce: capability.nonce, operationID: "operation",
            kind: .touchBarApply, actualParentPID: 123, actualExecutablePath: executable.path
        ))
    }

    func testWrongParentOperationAndKindAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex-headless")
        try Data("helper".utf8).write(to: executable)
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        _ = try journal.create(operationID: "operation")
        try journal.update { $0.stage = .handoffCommitted }
        let store = HelperCapabilityStore(directory: directory.appendingPathComponent("caps"), lockFile: directory.appendingPathComponent("caps.lock"), journalStore: journal)
        let capability = try store.reserve(kind: .softDisconnectApply, operationID: "operation", expectedParentPID: 123, expectedExecutablePath: executable.path)
        XCTAssertThrowsError(try store.consume(capabilityID: capability.capabilityID, nonce: capability.nonce, operationID: "other", kind: .softDisconnectApply, actualParentPID: 123, actualExecutablePath: executable.path))
        XCTAssertThrowsError(try store.consume(capabilityID: capability.capabilityID, nonce: capability.nonce, operationID: "operation", kind: .touchBarApply, actualParentPID: 123, actualExecutablePath: executable.path))
        XCTAssertThrowsError(try store.consume(capabilityID: capability.capabilityID, nonce: capability.nonce, operationID: "operation", kind: .softDisconnectApply, actualParentPID: 999, actualExecutablePath: executable.path))
    }

    func testExpiredCapabilityIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex-headless")
        try Data("helper".utf8).write(to: executable)
        let clock = FakeWorkflowClock()
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"), clock: clock)
        _ = try journal.create(operationID: "operation")
        let store = HelperCapabilityStore(directory: directory.appendingPathComponent("caps"), lockFile: directory.appendingPathComponent("caps.lock"), clock: clock, journalStore: journal)
        let capability = try store.reserve(kind: .keepAwakeHost, operationID: "operation", expectedParentPID: 123, expectedExecutablePath: executable.path, ttlSeconds: 1)
        clock.now = clock.now.addingTimeInterval(2)
        XCTAssertThrowsError(try store.consume(capabilityID: capability.capabilityID, nonce: capability.nonce, operationID: "operation", kind: .keepAwakeHost, actualParentPID: 123, actualExecutablePath: executable.path))
    }

    func testFutureCapabilitySchemaIsPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let caps = directory.appendingPathComponent("caps", isDirectory: true)
        try FileManager.default.createDirectory(at: caps, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = caps.appendingPathComponent("future.json")
        let original = Data(#"{"schemaVersion":99,"future":true}"#.utf8)
        try original.write(to: file)
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        let store = HelperCapabilityStore(directory: caps, lockFile: directory.appendingPathComponent("caps.lock"), journalStore: journal)
        XCTAssertThrowsError(try store.consume(capabilityID: "future", nonce: "x", operationID: "x", kind: .touchBarApply, actualParentPID: 1, actualExecutablePath: "/tmp/x"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testWrongJournalStageIsRejectedWithoutConsumingCapability() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex-headless")
        try Data("helper".utf8).write(to: executable)
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        _ = try journal.create(operationID: "operation")
        try journal.update { $0.stage = .handoffCommitted }
        let store = HelperCapabilityStore(directory: directory.appendingPathComponent("caps"), lockFile: directory.appendingPathComponent("caps.lock"), journalStore: journal)
        let capability = try store.reserve(kind: .touchBarApply, operationID: "operation", expectedParentPID: 123, expectedExecutablePath: executable.path)
        try journal.update { $0.stage = .enabling }
        XCTAssertThrowsError(try store.consume(
            capabilityID: capability.capabilityID, nonce: capability.nonce, operationID: "operation",
            kind: .touchBarApply, actualParentPID: 123, actualExecutablePath: executable.path
        ))
        try journal.update { $0.stage = .handoffCommitted }
        XCTAssertNoThrow(try store.consume(
            capabilityID: capability.capabilityID, nonce: capability.nonce, operationID: "operation",
            kind: .touchBarApply, actualParentPID: 123, actualExecutablePath: executable.path
        ))
    }
}
