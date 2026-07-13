import XCTest
@testable import CodexHeadlessCore

final class ShellExecutionTests: XCTestCase {
    func testLargeStdoutDoesNotDeadlock() throws {
        let result = try Shell.run("/bin/sh", ["-c", "i=0; while [ $i -lt 20000 ]; do printf 'stdout-line-%08d-abcdefghijklmnopqrstuvwxyz\\n' $i; i=$((i+1)); done"], timeoutSeconds: 5)
        XCTAssertTrue(result.succeeded)
        XCTAssertGreaterThan(result.output.utf8.count, 500_000)
        XCTAssertFalse(result.timedOut)
    }

    func testLargeStderrDoesNotDeadlock() throws {
        let result = try Shell.run("/bin/sh", ["-c", "i=0; while [ $i -lt 20000 ]; do printf 'stderr-line-%08d-abcdefghijklmnopqrstuvwxyz\\n' $i >&2; i=$((i+1)); done"], timeoutSeconds: 5)
        XCTAssertTrue(result.succeeded)
        XCTAssertGreaterThan(result.errorOutput.utf8.count, 500_000)
    }

    func testSimultaneousOutputIsDrained() throws {
        let result = try Shell.run("/bin/sh", ["-c", "i=0; while [ $i -lt 10000 ]; do echo out-$i; echo err-$i >&2; i=$((i+1)); done"], timeoutSeconds: 5)
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.output.contains("out-9999"))
        XCTAssertTrue(result.errorOutput.contains("err-9999"))
    }

    func testTimeoutIsExplicitAndRetainsOutput() throws {
        let result = try Shell.run("/bin/sh", ["-c", "echo before-timeout; trap '' TERM; while :; do sleep 1; done"], timeoutSeconds: 0.1)
        XCTAssertTrue(result.timedOut)
        XCTAssertTrue(result.output.contains("before-timeout"))
        XCTAssertGreaterThanOrEqual(result.durationMilliseconds, 100)
    }
}
