import XCTest
@testable import CodexHeadlessCore

final class OperationalSafetyPresentationTests: XCTestCase {
    func testNormalClassificationMappingRemainsSeparate() {
        XCTAssertEqual(OperationalSafetyPresentation.makeNormal(cleanAssessment()).title, "Clean Normal")
        XCTAssertEqual(OperationalSafetyPresentation.makeNormal(cleanAssessment(runtime: ["dirty"])).title, "Restore Required")
    }

    func testHealthyNonNormalModesUseOperationalEvidence() {
        XCTAssertEqual(presentation(.preparing).title, "Preparing managed handoff")
        XCTAssertEqual(presentation(.confirmRequired).title, "Awaiting confirmation")
        XCTAssertEqual(presentation(.headless).title, "Managed Headless active")
        XCTAssertEqual(presentation(.restoring).title, "Restoring Normal")
    }

    func testRefreshWithRecentEvidenceDoesNotFlicker() {
        let state = runtime(.headless)
        let evidence = operational(.headless)
        XCTAssertEqual(OperationalSafetyPresentation.make(state: state, availability: .refreshing(lastCompleted: evidence)).title, "Managed Headless active")
    }

    func testStaleAndUnavailableAreUnknownNotRecovery() {
        let state = runtime(.headless)
        XCTAssertEqual(OperationalSafetyPresentation.make(state: state, availability: .stale(operational(.headless))).title, "Unable to verify")
        XCTAssertEqual(OperationalSafetyPresentation.make(state: state, availability: .unavailable(nil)).title, "Unable to verify")
    }

    func testStructuredMissingJournalIsRecoveryRequired() {
        var evidence = operational(.headless)
        evidence.journal = .missingWhenRequired
        evidence.violations = [.journalMissing]
        XCTAssertEqual(OperationalSafetyPresentation.make(state: runtime(.headless), availability: .fresh(evidence)).title, "Recovery Required")
    }

    func testUnknownOwnerIsUnableToVerify() {
        var evidence = operational(.headless)
        evidence.keepAwake = .init(status: .unknown, summary: "unknown")
        evidence.violations = [.keepAwakeNotVerified(.unknown)]
        XCTAssertEqual(OperationalSafetyPresentation.make(state: runtime(.headless), availability: .fresh(evidence)).title, "Unable to verify")
    }

    func testExplicitErrorModeIsNotHiddenByGeneralEvidenceViolation() {
        var state = runtime(.error)
        state.lastError = "explicit workflow failure"
        var evidence = operational(.error)
        evidence.violations = [.journalMissing]
        XCTAssertEqual(OperationalSafetyPresentation.make(state: state, availability: .fresh(evidence)).title, "Error - review status")
    }

    private func presentation(_ mode: HeadlessMode) -> OperationalSafetyPresentation {
        OperationalSafetyPresentation.make(state: runtime(mode), availability: .fresh(operational(mode)))
    }

    private func runtime(_ mode: HeadlessMode) -> RuntimeState { var value = RuntimeState.default; value.mode = mode; return value }
    private func operational(_ mode: HeadlessMode) -> OperationalEvidence {
        .init(capturedAt: Date(), source: .periodicReconcile, runtimeMode: mode, operationID: "op", phase: .headlessActive,
              runtimeReadStatus: .success, journal: .activeConsistent(operationID: "op", stage: .headless),
              processSnapshot: .success(durationMilliseconds: 1),
              keepAwake: .init(status: .verifiedOwned, summary: "owned", pid: 1), virtualDisplay: .none,
              display: .init(expectedManagedDisplayID: nil, observedManagedDisplayID: nil, managedDisplayEnumerated: false, expectedDisplayMatchesObserved: nil, physicalMainDisplayID: 1, builtInPresent: false), violations: [])
    }
    private func cleanAssessment(runtime: [String] = []) -> CleanNormalAssessment {
        .init(runtimeViolations: runtime, journalViolation: nil, observedResourceViolations: [], displayViolations: [], keepAwakeObservation: .none, virtualDisplayObservation: .none)
    }
}
