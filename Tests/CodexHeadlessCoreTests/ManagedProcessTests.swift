import XCTest
@testable import CodexHeadlessCore

final class ManagedProcessTests: XCTestCase {
    private let facts = ManagedProcessFacts(
        pid: 42,
        command: "/bin/sh marker instance-1",
        executableCanonicalPath: "/bin/sh",
        executableFileIdentity: "1:2",
        processStartTime: "start-1"
    )

    func testMatchingIdentity() {
        XCTAssertTrue(identity().matches(facts: facts))
    }

    func testPIDReuseIsRejected() {
        var reused = facts
        reused.processStartTime = "start-2"
        XCTAssertFalse(identity().matches(facts: reused))
    }

    func testExecutableMismatchIsRejected() {
        var mismatch = facts
        mismatch.executableCanonicalPath = "/usr/bin/false"
        XCTAssertFalse(identity().matches(facts: mismatch))
    }

    func testFileIdentityMismatchIsRejected() {
        var mismatch = facts
        mismatch.executableFileIdentity = "9:9"
        XCTAssertFalse(identity().matches(facts: mismatch))
    }

    func testCommandAndInstanceMismatchAreRejected() {
        var mismatch = facts
        mismatch.command = "/bin/sh another-marker"
        XCTAssertFalse(identity().matches(facts: mismatch))
    }

    private func identity() -> ManagedProcessIdentity {
        ManagedProcessIdentity(
            pid: 42,
            executablePath: "/bin/sh",
            requiredCommandFragments: ["marker", "instance-1"],
            expectedStartTime: "start-1",
            expectedExecutableFileIdentity: "1:2"
        )
    }
}
