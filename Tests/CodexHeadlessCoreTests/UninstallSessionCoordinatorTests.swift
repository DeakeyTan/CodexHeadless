import XCTest
@testable import CodexHeadlessCore

final class UninstallSessionCoordinatorTests: XCTestCase {
    func testLockRemainsHeldThroughOrderedDeletion() throws {
        let setup = try makeSetup()
        let result = setup.coordinator.execute(setup.request)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(setup.deleter.removed, [setup.request.launchAgentURL, setup.request.installedAppURL, setup.request.installedCLIURL])
        XCTAssertTrue(setup.deleter.lockHeldForEveryRemoval)
        XCTAssertTrue(setup.lease.released)
        XCTAssertTrue(setup.barrier.completed)
    }

    func testUnsafePreflightPreservesEveryTarget() throws {
        let setup = try makeSetup(mode: .headless)
        XCTAssertNotEqual(setup.coordinator.execute(setup.request), .completed)
        XCTAssertTrue(setup.deleter.removed.isEmpty)
    }

    func testEntryPointFailureOccursBeforeDeletion() throws {
        let setup = try makeSetup(entryFailure: "App remains")
        XCTAssertEqual(setup.coordinator.execute(setup.request), .refused("App remains"))
        XCTAssertTrue(setup.deleter.removed.isEmpty)
    }

    func testAppDeletionFailurePreservesCLI() throws {
        let setup = try makeSetup(failAtRemoval: 1)
        guard case .failed(let reason) = setup.coordinator.execute(setup.request) else { return XCTFail("expected failure") }
        XCTAssertTrue(reason.contains("CLI was preserved"))
        XCTAssertFalse(setup.deleter.removed.contains(setup.request.installedCLIURL))
    }

    func testCLIDeletionFailureReportsRemainingPath() throws {
        let setup = try makeSetup(failAtRemoval: 2)
        guard case .failed(let reason) = setup.coordinator.execute(setup.request) else { return XCTFail("expected failure") }
        XCTAssertTrue(reason.contains(setup.request.installedCLIURL.path))
    }

    func testPathTraversalAndOutsideSymlinkAreRefused() throws {
        let setup = try makeSetup()
        var traversal = setup.request
        traversal.installedAppURL = setup.request.testRootURL!.appendingPathComponent("../escape")
        XCTAssertThrowsError(try UninstallSessionPathPolicy.validate(traversal))

        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = setup.request.testRootURL!.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        var symlink = setup.request
        symlink.installedAppURL = link
        XCTAssertThrowsError(try UninstallSessionPathPolicy.validate(symlink))
    }

    func testConcurrentProcessCannotAcquireLockUntilDeletionCompletes() throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("CodexHeadless-uninstall-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lockFile = root.appendingPathComponent("workflow.lock")
        let state = StateStore(stateFile: root.appendingPathComponent("state.json"), lockFile: root.appendingPathComponent("state.lock")); try state.write(.default)
        let journal = RecoveryJournalStore(journalFile: root.appendingPathComponent("journal.json"), lockFile: root.appendingPathComponent("journal.lock"))
        let lock = WorkflowOperationLock(lockFile: lockFile)
        let checker = UninstallSafetyChecker(stateStore: state, recoveryJournalStore: journal, assessor: FixedSessionAssessor(value: cleanAssessment(mode: .normal)), operationLock: lock)
        let barrier = BlockingBarrier()
        let coordinator = UninstallSessionCoordinator(operationLock: lock, safetyChecker: checker, entryPoints: TrackingEntryPoints(failure: nil), deleter: NoopDeleter(), barrier: barrier)
        let request = UninstallSessionRequest(installedAppURL: root.appendingPathComponent("app"), installedCLIURL: root.appendingPathComponent("cli"), launchAgentURL: root.appendingPathComponent("agent"), testRootURL: root)
        let finished = expectation(description: "session")
        DispatchQueue.global().async { _ = coordinator.execute(request); finished.fulfill() }
        XCTAssertEqual(barrier.ready.wait(timeout: .now() + 2), .success)

        let helper = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("CodexHeadlessTestHelper")
        let process = Process(); process.executableURL = helper; process.arguments = ["lock-attempt", "--path", lockFile.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 2)
        XCTAssertFalse(barrier.completed)
        barrier.proceed.signal()
        wait(for: [finished], timeout: 2)
        XCTAssertTrue(barrier.completed)
    }

    func testLaunchAgentPrintClassificationIsFailClosed() {
        XCTAssertEqual(SystemUninstallEntryPointManager.classifyLaunchAgentPrint(shellResult(exitCode: 0)), .loaded)
        XCTAssertEqual(
            SystemUninstallEntryPointManager.classifyLaunchAgentPrint(shellResult(exitCode: 113, error: "Could not find service com.codexheadless.app")),
            .notLoaded
        )
        XCTAssertEqual(
            SystemUninstallEntryPointManager.classifyLaunchAgentPrint(shellResult(exitCode: 1, timedOut: true)),
            .unverified("launchctl print timed out")
        )
        guard case .unverified = SystemUninstallEntryPointManager.classifyLaunchAgentPrint(
            shellResult(exitCode: 9, reason: .uncaughtSignal)
        ) else { return XCTFail("signal must remain unverified") }
        guard case .unverified = SystemUninstallEntryPointManager.classifyLaunchAgentPrint(
            shellResult(exitCode: 77, error: "domain access denied")
        ) else { return XCTFail("unknown failure must remain unverified") }
        guard case .unverified = SystemUninstallEntryPointManager.classifyLaunchAgentPrint(
            shellResult(exitCode: 1)
        ) else { return XCTFail("empty failure must remain unverified") }
    }

    func testLaunchAgentExecutionErrorIsUnverified() {
        let manager = SystemUninstallEntryPointManager { _ in throw FakeError.requested }
        guard case .unverified(let reason) = manager.observeLaunchAgent(service: "gui/1/test") else {
            return XCTFail("execution errors must remain unverified")
        }
        XCTAssertTrue(reason.contains("could not be executed"))
    }

    func testUnverifiedLaunchAgentPreservesAppAndCLI() throws {
        let setup = try makeSetup(entryFailure: "LaunchAgent unverified")
        XCTAssertEqual(setup.coordinator.execute(setup.request), .refused("LaunchAgent unverified"))
        XCTAssertTrue(setup.deleter.removed.isEmpty)
    }

    private func shellResult(
        exitCode: Int32,
        reason: Process.TerminationReason = .exit,
        error: String = "",
        timedOut: Bool = false
    ) -> ShellResult {
        .init(exitCode: exitCode, terminationReason: reason, output: "", errorOutput: error, timedOut: timedOut, durationMilliseconds: 1)
    }

    private func makeSetup(
        mode: HeadlessMode = .normal,
        entryFailure: String? = nil,
        failAtRemoval: Int? = nil
    ) throws -> Setup {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("CodexHeadless-uninstall-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let state = StateStore(stateFile: root.appendingPathComponent("state.json"), lockFile: root.appendingPathComponent("state.lock"))
        var runtime = RuntimeState.default; runtime.mode = mode; try state.write(runtime)
        let journal = RecoveryJournalStore(journalFile: root.appendingPathComponent("journal.json"), lockFile: root.appendingPathComponent("journal.lock"))
        let assessor = FixedSessionAssessor(value: cleanAssessment(mode: mode))
        let lease = TrackingLease()
        let lock = TrackingLock(lease: lease)
        let checker = UninstallSafetyChecker(stateStore: state, recoveryJournalStore: journal, assessor: assessor, operationLock: lock)
        let deleter = TrackingDeleter(lease: lease, failAt: failAtRemoval)
        let barrier = TrackingBarrier()
        let coordinator = UninstallSessionCoordinator(
            operationLock: lock, safetyChecker: checker,
            entryPoints: TrackingEntryPoints(failure: entryFailure),
            deleter: deleter, barrier: barrier
        )
        return Setup(coordinator: coordinator, request: .init(
            installedAppURL: root.appendingPathComponent("Applications/CodexHeadless.app"),
            installedCLIURL: root.appendingPathComponent("usr/local/bin/codex-headless"),
            launchAgentURL: root.appendingPathComponent("home/Library/LaunchAgents/com.codexheadless.app.plist"),
            testRootURL: root
        ), lease: lease, deleter: deleter, barrier: barrier)
    }

    private func cleanAssessment(mode: HeadlessMode) -> CleanNormalAssessment {
        .init(runtimeViolations: mode == .normal ? [] : ["mode"], journalViolation: nil,
              observedResourceViolations: [], displayViolations: [],
              keepAwakeObservation: .none, virtualDisplayObservation: .none)
    }
}

private struct Setup { let coordinator: UninstallSessionCoordinator; let request: UninstallSessionRequest; let lease: TrackingLease; let deleter: TrackingDeleter; let barrier: TrackingBarrier }
private struct FixedSessionAssessor: CleanNormalAssessing { let value: CleanNormalAssessment; func assess(allowingFinalizingJournalOperationID: String?, snapshot: ManagedProcessSnapshot?) -> CleanNormalAssessment { value } }
private final class TrackingLease: WorkflowOperationLeaseHandling { let operationID = "uninstall"; var released = false; func release() { released = true } }
private final class TrackingLock: WorkflowOperationLocking { let lease: TrackingLease; init(lease: TrackingLease) { self.lease = lease }; func acquire(name: String, timeoutSeconds: TimeInterval, logLifecycle: Bool) throws -> WorkflowOperationLeaseHandling { lease } }
private final class TrackingEntryPoints: UninstallEntryPointManaging { let failure: String?; init(failure: String?) { self.failure = failure }; func stopAndVerify(launchAgentURL: URL, appExecutableURL: URL) -> String? { failure } }
private final class TrackingDeleter: UninstallFileDeleting {
    let lease: TrackingLease; let failAt: Int?; var removed: [URL] = []; var lockHeldForEveryRemoval = true
    init(lease: TrackingLease, failAt: Int?) { self.lease = lease; self.failAt = failAt }
    func remove(_ url: URL) throws { lockHeldForEveryRemoval = lockHeldForEveryRemoval && !lease.released; if removed.count == failAt { throw FakeError.requested }; removed.append(url) }
}
private final class TrackingBarrier: UninstallSessionBarrierHandling { var completed = false; func afterPreflight() throws {}; func deletionCompleted() throws { completed = true } }
private final class NoopDeleter: UninstallFileDeleting { func remove(_ url: URL) throws {} }
private final class BlockingBarrier: UninstallSessionBarrierHandling {
    let ready = DispatchSemaphore(value: 0); let proceed = DispatchSemaphore(value: 0); var completed = false
    func afterPreflight() throws { ready.signal(); proceed.wait() }
    func deletionCompleted() throws { completed = true }
}
