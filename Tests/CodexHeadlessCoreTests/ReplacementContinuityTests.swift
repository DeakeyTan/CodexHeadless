import XCTest
@testable import CodexHeadlessCore

final class ReplacementContinuityTests: XCTestCase {
    func testHealthyReplacementDoesNotCreateSuspect() {
        let state = runtime()
        XCTAssertNil(ReplacementLossSuspect(state: state, evidence: evidence(missing: false)))
    }

    func testFirstTrustedMissingObservationCreatesWorkflowBoundSuspect() throws {
        let suspect = try XCTUnwrap(ReplacementLossSuspect(state: runtime(), evidence: evidence(missing: true)))
        XCTAssertEqual(suspect.runtimeMode, .headless)
        XCTAssertEqual(suspect.operationID, "operation-a")
        XCTAssertEqual(suspect.replacementDisplayID, 2)
        XCTAssertTrue(suspect.stillMatches(state: runtime(), evidence: evidence(missing: true)))
    }

    func testReappearanceModeOrOperationChangeCancelsConfirmation() throws {
        let suspect = try XCTUnwrap(ReplacementLossSuspect(state: runtime(), evidence: evidence(missing: true)))
        XCTAssertFalse(suspect.stillMatches(state: runtime(), evidence: evidence(missing: false)))
        var normal = runtime(); normal.mode = .normal
        XCTAssertFalse(suspect.stillMatches(state: normal, evidence: evidence(missing: true)))
        XCTAssertFalse(suspect.stillMatches(state: runtime(), evidence: evidence(missing: true, operationID: "operation-b")))
    }

    func testUnreadableEvidenceAndUnknownManagedOwnerNeverCreateSuspect() {
        var unreadable = evidence(missing: true)
        unreadable.processSnapshot = .failed("unavailable")
        XCTAssertNil(ReplacementLossSuspect(state: runtime(), evidence: unreadable))

        var managedState = runtime(); managedState.virtualDisplayCreated = true; managedState.virtualDisplayID = 2
        var unknown = evidence(missing: true)
        unknown.virtualDisplay = .init(status: .unknown, summary: "unknown")
        XCTAssertNil(ReplacementLossSuspect(state: managedState, evidence: unknown))
        unknown.virtualDisplay = .none
        XCTAssertNotNil(ReplacementLossSuspect(state: managedState, evidence: unknown))
    }

    private func runtime() -> RuntimeState {
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.replacementDisplayID = 2
        return state
    }

    private func evidence(missing: Bool, operationID: String = "operation-a") -> OperationalEvidence {
        .init(
            capturedAt: Date(), source: .periodicReconcile, runtimeMode: .headless,
            operationID: operationID, phase: .headlessActive, runtimeReadStatus: .success,
            journal: .activeConsistent(operationID: operationID, stage: .headless),
            processSnapshot: .success(durationMilliseconds: 1),
            keepAwake: .init(status: .verifiedOwned, summary: "owned"), virtualDisplay: .none,
            display: .init(
                expectedManagedDisplayID: nil, observedManagedDisplayID: nil, managedDisplayEnumerated: false,
                expectedDisplayMatchesObserved: nil, physicalMainDisplayID: 2, builtInPresent: false,
                expectedReplacementDisplayID: 2, replacementDisplayEnumerated: !missing,
                replacementDisplayActive: !missing, replacementDisplayOnline: !missing,
                replacementDisplayMain: !missing, replacementDisplayManagedVirtual: false
            ),
            violations: missing ? [.replacementDisplayMissing(2)] : []
        )
    }
}
