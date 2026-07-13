import XCTest
@testable import CodexHeadlessCore

final class RecoveryJournalCompatibilityTests: XCTestCase {
    func testFutureSchemaIsPreservedWithoutBackupOrOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("recovery-journal.json")
        let original = Data(#"{"schemaVersion":99,"operationID":"future","futureField":true}"#.utf8)
        try original.write(to: file)
        let store = RecoveryJournalStore(journalFile: file, lockFile: directory.appendingPathComponent("lock"))

        XCTAssertThrowsError(try store.read()) { error in
            guard case RecoveryJournalStoreError.unsupportedSchema(99) = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains("damaged") }.isEmpty)
        XCTAssertThrowsError(try store.create(operationID: "old"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testRestorePreservesFutureJournalAndDoesNotCleanup() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        let file = harness.directory.appendingPathComponent("recovery-journal.json")
        let original = Data(#"{"schemaVersion":99,"operationID":"future","futureField":true}"#.utf8)
        try original.write(to: file)
        let result = harness.controller.restoreNormal()
        guard case .recoveryRequired = result else { return XCTFail("expected recoveryRequired") }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(harness.virtual.destroyCallCount, 0)
        XCTAssertEqual(harness.sleep.disableCallCount, 0)
    }
}
