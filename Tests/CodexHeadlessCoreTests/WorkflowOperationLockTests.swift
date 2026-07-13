import Foundation
import XCTest
@testable import CodexHeadlessCore

final class WorkflowOperationLockTests: XCTestCase {
    func testSecondLockTimesOutWhileFirstLeaseIsHeld() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHeadless-OperationLockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("operation.lock")
        let first = WorkflowOperationLock(lockFile: lockURL)
        let second = WorkflowOperationLock(lockFile: lockURL)
        let lease = try first.acquire(name: "first", timeoutSeconds: 1, logLifecycle: false)
        defer { lease.release() }

        XCTAssertThrowsError(try second.acquire(name: "second", timeoutSeconds: 0.05, logLifecycle: false)) { error in
            guard case StateStoreError.lockTimeout = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLockCanBeAcquiredAfterRelease() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHeadless-OperationLockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lock = WorkflowOperationLock(lockFile: directory.appendingPathComponent("operation.lock"))
        let first = try lock.acquire(name: "first", timeoutSeconds: 1, logLifecycle: false)
        first.release()
        let second = try lock.acquire(name: "second", timeoutSeconds: 1, logLifecycle: false)
        second.release()
    }
}
