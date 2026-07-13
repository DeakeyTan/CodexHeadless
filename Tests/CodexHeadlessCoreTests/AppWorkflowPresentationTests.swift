import XCTest
@testable import CodexHeadlessCore

final class AppWorkflowPresentationTests: XCTestCase {
    func testPausedEnableFailureDoesNotRequestErrorState() {
        let presentation = AppEnableFailurePresentation.make(outcome: .pausedWithReplacement, message: "failed")
        XCTAssertFalse(presentation.shouldMarkError)
        XCTAssertTrue(presentation.message.contains("safely paused"))
    }

    func testRecoveryRequiredDoesNotRequestErrorState() {
        XCTAssertFalse(AppEnableFailurePresentation.make(outcome: .recoveryRequired, message: "failed").shouldMarkError)
    }

    func testUnsafeFailureRequestsErrorState() {
        XCTAssertTrue(AppEnableFailurePresentation.make(outcome: .unsafeFailure, message: "failed").shouldMarkError)
    }

    func testEveryRestoreResultHasAccuratePresentation() {
        XCTAssertTrue(AppRestorePresentation.make(result: .completed).isSuccess)
        XCTAssertTrue(AppRestorePresentation.make(result: .alreadyNormal).isSuccess)
        XCTAssertFalse(AppRestorePresentation.make(result: .pausedForSafety(reason: "wait")).isSuccess)
        XCTAssertFalse(AppRestorePresentation.make(result: .recoveryRequired(reason: "journal")).isSuccess)
        XCTAssertFalse(AppRestorePresentation.make(result: .cleanupIncomplete(progress: .init(), reason: "cleanup")).isSuccess)
        XCTAssertFalse(AppRestorePresentation.make(result: .failed(reason: "failure")).isSuccess)
    }

    func testTerminationGateRejectsEveryManagedResource() {
        XCTAssertNil(AppTerminationGate.blockReason(.init(state: .default, recoveryJournalActive: false, operationBusy: false)))
        var state = RuntimeState.default
        state.virtualDisplayCreated = true
        XCTAssertNotNil(AppTerminationGate.blockReason(.init(state: state, recoveryJournalActive: false, operationBusy: false)))
        XCTAssertNotNil(AppTerminationGate.blockReason(.init(state: .default, recoveryJournalActive: true, operationBusy: false)))
        XCTAssertNotNil(AppTerminationGate.blockReason(.init(state: .default, recoveryJournalActive: false, operationBusy: true)))
    }
}
