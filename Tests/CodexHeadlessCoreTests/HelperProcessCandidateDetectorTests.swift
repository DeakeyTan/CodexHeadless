import XCTest
@testable import CodexHeadlessCore

final class HelperProcessCandidateDetectorTests: XCTestCase {
    func testUnrelatedCommandsAreNotCandidates() {
        let commands = [
            "/usr/bin/grep internal-helper virtual-display-host",
            "/bin/sh -c 'echo internal-helper virtual-display-host'",
            "/Applications/Codex.app/Contents/MacOS/Codex prompt internal-helper virtual-display-host",
            "/tmp/TestRunner --argument=internal-helper --argument=virtual-display-host",
            "/Applications/Editor.app/Contents/MacOS/Editor /src/internal-helper/virtual-display-host.swift"
        ]
        for (index, command) in commands.enumerated() {
            let snapshot = snapshot(pid: Int32(index + 10), command: command)
            XCTAssertNil(HelperProcessCandidateDetector.candidatePID(in: snapshot, kind: .virtualDisplayHost), command)
        }
    }

    func testExactHelperCommandWithVerifiedFactsIsDetected() {
        let command = "/usr/local/bin/codex-headless internal-helper virtual-display-host capability nonce operation instance 1920 1080 60 hidpi"
        let inspector = CandidateInspector(facts: ManagedProcessFacts(
            pid: 42, command: command, executableCanonicalPath: "/usr/local/bin/codex-headless",
            executableFileIdentity: "1:2", processStartTime: "start"
        ))
        XCTAssertEqual(
            HelperProcessCandidateDetector.verify(
                snapshot: snapshot(pid: 42, command: command), kind: .virtualDisplayHost,
                inspector: inspector, excludingPID: 999
            ),
            .verified(pid: 42)
        )
    }

    func testStrongCandidateWithUnavailableFactsIsUnknown() {
        let command = "/usr/local/bin/codex-headless internal-helper keep-awake-host capability nonce operation instance"
        XCTAssertEqual(
            HelperProcessCandidateDetector.verify(
                snapshot: snapshot(pid: 43, command: command), kind: .keepAwakeHost,
                inspector: CandidateInspector(facts: nil), excludingPID: 999
            ),
            .unknown(pid: 43, reason: "helper-shaped process identity could not be collected")
        )
    }

    private func snapshot(pid: Int32, command: String) -> ManagedProcessSnapshot {
        ManagedProcessSnapshot(
            capturedAt: Date(), entries: [.init(pid: pid, command: command)],
            succeeded: true, error: nil, durationMilliseconds: 1
        )
    }
}

private final class CandidateInspector: ManagedProcessInspecting {
    let value: ManagedProcessFacts?
    init(facts: ManagedProcessFacts?) { value = facts }
    func isRunning(pid: Int32) -> Bool { value?.pid == pid }
    func command(pid: Int32) -> String? { value?.command }
    func matches(_ identity: ManagedProcessIdentity) -> Bool { value.map(identity.matches) ?? false }
    func terminate(_ identity: ManagedProcessIdentity, timeoutSeconds: TimeInterval) -> ManagedResourceCleanupResult { .alreadyStopped }
    func facts(pid: Int32) -> ManagedProcessFacts? { value?.pid == pid ? value : nil }
}
