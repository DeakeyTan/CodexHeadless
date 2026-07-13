import Darwin
import Foundation
import XCTest
@testable import CodexHeadlessCore

final class StateStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHeadless-StateStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testConcurrentTransactionsDoNotLoseUpdates() throws {
        let stateURL = directory.appendingPathComponent("state.json")
        let lockURL = directory.appendingPathComponent("state.lock")
        let stores = (0..<8).map { _ in
            StateStore(stateFile: stateURL, lockFile: lockURL, lockTimeoutSeconds: 5)
        }
        try stores[0].write(.default)

        let queue = DispatchQueue(label: "state-stress", attributes: .concurrent)
        let group = DispatchGroup()
        let errors = ErrorCollector()
        for index in 0..<100 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    try stores[index % stores.count].transaction { state in
                        let current = Int(state.phaseMessage ?? "0") ?? 0
                        state.phaseMessage = String(current + 1)
                    }
                } catch {
                    errors.append(error)
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(errors.values.isEmpty, "\(errors.values)")
        XCTAssertEqual(try stores[0].read().phaseMessage, "100")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)))
    }

    func testLockTimeoutIsExplicit() throws {
        let stateURL = directory.appendingPathComponent("state.json")
        let lockURL = directory.appendingPathComponent("state.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        XCTAssertEqual(flock(descriptor, LOCK_EX), 0)
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
        let store = StateStore(stateFile: stateURL, lockFile: lockURL, lockTimeoutSeconds: 0.05)
        XCTAssertThrowsError(try store.read()) { error in
            guard case StateStoreError.lockTimeout = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCorruptedStateRequiresExplicitVerifiedReplacement() throws {
        let stateURL = directory.appendingPathComponent("state.json")
        let lockURL = directory.appendingPathComponent("state.lock")
        try Data("not-json".utf8).write(to: stateURL)
        let store = StateStore(stateFile: stateURL, lockFile: lockURL)
        XCTAssertEqual(store.load().mode, .recoveryRequired)
        XCTAssertThrowsError(try store.transaction { state in
            state.mode = .restoring
            state.phase = .restorePaused
        })
        XCTAssertEqual(String(data: try Data(contentsOf: stateURL), encoding: .utf8), "not-json")
        var replacement = RuntimeState.default
        replacement.mode = .restoring
        replacement.phase = .restorePaused
        try store.replaceCorruptedStateAfterVerifiedRecovery(replacement)
        XCTAssertEqual(try store.read().mode, .restoring)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("state.damaged.") }.isEmpty)
    }

    func testDamagedStateBackupIsDeduplicated() throws {
        let stateURL = directory.appendingPathComponent("state.json")
        let lockURL = directory.appendingPathComponent("state.lock")
        try Data("same-damage".utf8).write(to: stateURL)
        let store = StateStore(stateFile: stateURL, lockFile: lockURL)
        _ = store.load()
        _ = store.load()
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("state.damaged.") }
        XCTAssertEqual(backups.count, 1)
    }
}

private final class ErrorCollector {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ error: Error) {
        lock.lock()
        storage.append(error)
        lock.unlock()
    }
}
