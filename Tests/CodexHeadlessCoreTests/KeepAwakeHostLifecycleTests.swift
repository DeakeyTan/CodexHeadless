import XCTest
@testable import CodexHeadlessCore

final class KeepAwakeHostLifecycleTests: XCTestCase {
    func testRecordedPIDIsTheAssertionHolderPID() {
        let ownership = ManagedProcessOwnershipRecord(
            instanceID: "holder", pid: 42, executableCanonicalPath: "/tmp/codex-headless",
            executableFileIdentity: "1:2", processStartTime: "start",
            expectedCommandFragments: ["internal-helper", "keep-awake-host"],
            ownerOperationID: "operation", resourceKind: "keep-awake", createdAt: Date()
        )
        let record = KeepAwakeHostRecord(
            instanceID: "holder", pid: 42, backend: .caffeinate,
            executablePath: "/tmp/codex-headless", startedAt: Date(), ownerProcessKind: "cli",
            ownership: ownership, assertionKind: "PreventUserIdleSystemSleep"
        )
        XCTAssertEqual(record.pid, record.ownership?.pid)
        XCTAssertEqual(record.assertionKind, "PreventUserIdleSystemSleep")
    }

    func testPIDReuseNeverMatchesOwnedHolder() {
        let identity = ManagedProcessIdentity(
            pid: 42, executablePath: "/tmp/codex-headless",
            requiredCommandFragments: ["internal-helper", "keep-awake-host"],
            expectedStartTime: "original", expectedExecutableFileIdentity: "1:2"
        )
        let reused = ManagedProcessFacts(
            pid: 42, command: "/tmp/codex-headless internal-helper keep-awake-host",
            executableCanonicalPath: "/tmp/codex-headless", executableFileIdentity: "1:2",
            processStartTime: "reused"
        )
        XCTAssertFalse(identity.matches(facts: reused))
    }
}
