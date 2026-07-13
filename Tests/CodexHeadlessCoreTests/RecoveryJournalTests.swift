import XCTest
@testable import CodexHeadlessCore

final class RecoveryJournalTests: XCTestCase {
    func testCreateUpdateReadDelete() throws {
        let harness = try JournalHarness()
        let created = try harness.store.create(operationID: "operation-1")
        XCTAssertEqual(created.stage, .enabling)
        try harness.store.update {
            $0.builtInDisplayID = 1
            $0.builtInSoftDisconnected = true
            $0.stage = .builtInSoftDisconnected
        }
        XCTAssertEqual(try harness.store.read()?.builtInDisplayID, 1)
        XCTAssertEqual(try harness.store.read()?.stage, .builtInSoftDisconnected)
        try harness.store.delete()
        XCTAssertNil(try harness.store.read())
    }

    func testDamagedJournalIsBackedUpAndRejected() throws {
        let harness = try JournalHarness()
        try Data("damaged".utf8).write(to: harness.file)
        XCTAssertThrowsError(try harness.store.read())
        let backups = try FileManager.default.contentsOfDirectory(atPath: harness.directory.path)
        XCTAssertTrue(backups.contains { $0.hasPrefix("recovery-journal.damaged.") })
    }

    func testFutureSchemaIsRejectedWithoutReplacement() throws {
        let harness = try JournalHarness()
        var journal = RecoveryJournal(operationID: "future", createdAt: Date())
        journal.schemaVersion = RecoveryJournal.currentSchemaVersion + 1
        try JSONEncoder().encode(journal).write(to: harness.file)
        XCTAssertThrowsError(try harness.store.read())
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.file.path))
    }
}

private final class JournalHarness {
    let directory: URL
    let file: URL
    let store: RecoveryJournalStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RecoveryJournalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("recovery-journal.json")
        store = RecoveryJournalStore(journalFile: file, lockFile: directory.appendingPathComponent("recovery-journal.lock"))
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
