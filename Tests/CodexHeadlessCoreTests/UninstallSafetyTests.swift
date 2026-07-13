import XCTest
@testable import CodexHeadlessCore

final class UninstallSafetyTests: XCTestCase {
    func testCleanNormalIsSafe() throws {
        let setup = try makeSetup()
        XCTAssertEqual(setup.checker.check().status, .safe)
    }

    func testEveryUnsafeModeIsRefused() throws {
        for mode in [HeadlessMode.preparing, .confirmRequired, .headless, .restoring, .fallback, .error, .recoveryRequired] {
            let setup = try makeSetup(mode: mode, assessment: assessment(runtime: ["mode is \(mode.rawValue)"]))
            let result = setup.checker.check()
            XCTAssertEqual(result.status, .refused, "mode \(mode)")
            XCTAssertEqual(result.exitCode, CLIExitCode.safetyRefusal)
        }
    }

    func testActiveJournalIsRefusedEvenWhenAssessmentClaimsClean() throws {
        let setup = try makeSetup()
        _ = try setup.journal.create(operationID: "active")
        XCTAssertEqual(setup.checker.check().status, .refused)
    }

    func testManagedResourceResidueIsRefused() throws {
        for value in [
            assessment(runtime: ["Keep Awake remains"]),
            assessment(runtime: ["virtual display remains"], managedDisplay: true)
        ] {
            XCTAssertEqual(try makeSetup(assessment: value).checker.check().status, .refused)
        }
    }

    func testUnknownProcessEvidenceIsUnverified() throws {
        let value = assessment(snapshotSucceeded: false)
        let result = try makeSetup(assessment: value).checker.check()
        XCTAssertEqual(result.status, .unverified)
        XCTAssertEqual(result.exitCode, CLIExitCode.failure)
    }

    func testUnknownOwnerEvidenceIsUnverified() throws {
        let value = assessment(keepAwake: .init(status: .unknown, summary: "facts unavailable"))
        XCTAssertEqual(try makeSetup(assessment: value).checker.check().status, .unverified)
    }

    func testRuntimeReadFailureIsUnverified() throws {
        let setup = try makeSetup()
        let checker = UninstallSafetyChecker(
            stateStore: ThrowingReadStateStore(),
            recoveryJournalStore: setup.journal,
            assessor: FixedCleanNormalAssessor(value: assessment()),
            operationLock: FakeWorkflowOperationLock()
        )
        XCTAssertEqual(checker.check().status, .unverified)
    }

    func testJournalReadFailureIsUnverified() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = StateStore(
            stateFile: directory.appendingPathComponent("state.json"),
            lockFile: directory.appendingPathComponent("state.lock")
        )
        try state.write(.default)
        let checker = UninstallSafetyChecker(
            stateStore: state,
            recoveryJournalStore: ThrowingJournalStore(),
            assessor: FixedCleanNormalAssessor(value: assessment()),
            operationLock: FakeWorkflowOperationLock()
        )
        XCTAssertEqual(checker.check().status, .unverified)
    }

    private func makeSetup(
        mode: HeadlessMode = .normal,
        assessment value: CleanNormalAssessment? = nil
    ) throws -> (checker: UninstallSafetyChecker, journal: RecoveryJournalStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = StateStore(stateFile: directory.appendingPathComponent("state.json"), lockFile: directory.appendingPathComponent("state.lock"))
        var runtime = RuntimeState.default
        runtime.mode = mode
        try state.write(runtime)
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        return (
            UninstallSafetyChecker(
                stateStore: state,
                recoveryJournalStore: journal,
                assessor: FixedCleanNormalAssessor(value: value ?? assessment()),
                operationLock: FakeWorkflowOperationLock()
            ),
            journal
        )
    }

    private func assessment(
        runtime: [String] = [],
        snapshotSucceeded: Bool = true,
        managedDisplay: Bool = false,
        keepAwake: ManagedResourceObservation = .none
    ) -> CleanNormalAssessment {
        .init(
            runtimeViolations: runtime,
            journalViolation: nil,
            observedResourceViolations: [],
            displayViolations: managedDisplay ? ["managed display"] : [],
            keepAwakeObservation: keepAwake,
            virtualDisplayObservation: .none,
            processSnapshotSucceeded: snapshotSucceeded,
            processSnapshotError: snapshotSucceeded ? nil : "snapshot failed",
            managedDisplayViolation: managedDisplay
        )
    }
}

private struct FixedCleanNormalAssessor: CleanNormalAssessing {
    let value: CleanNormalAssessment
    func assess(allowingFinalizingJournalOperationID: String?, snapshot: ManagedProcessSnapshot?) -> CleanNormalAssessment { value }
}

private final class ThrowingReadStateStore: RuntimeStateStoring {
    func load() -> RuntimeState { .default }
    func save(_ state: RuntimeState) throws { throw FakeError.requested }
    func read() throws -> RuntimeState { throw FakeError.requested }
    func write(_ state: RuntimeState) throws { throw FakeError.requested }
    func transaction<T>(_ mutation: (inout RuntimeState) throws -> T) throws -> T { throw FakeError.requested }
    func replaceCorruptedStateAfterVerifiedRecovery(_ state: RuntimeState) throws { throw FakeError.requested }
    func bestEffortUpdate(_ mutation: (inout RuntimeState) -> Void) {}
}

private final class ThrowingJournalStore: RecoveryJournalStoring {
    func read() throws -> RecoveryJournal? { throw FakeError.requested }
    func create(operationID: String) throws -> RecoveryJournal { throw FakeError.requested }
    func update(_ mutation: (inout RecoveryJournal) throws -> Void) throws { throw FakeError.requested }
    func delete() throws { throw FakeError.requested }
}
