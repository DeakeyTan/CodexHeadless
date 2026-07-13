import XCTest
@testable import CodexHeadlessCore

final class OperationalTransitionDiagnosticTests: XCTestCase {
    func testTimestampSourceAndSnapshotDurationDoNotCreateDiagnosticNoise() {
        let first = evidence(date: Date(timeIntervalSince1970: 1), source: .launch, duration: 2)
        let second = evidence(date: Date(timeIntervalSince1970: 20), source: .periodicReconcile, duration: 99)
        let presentation = OperationalSafetyPresentation.make(state: runtime(), availability: .fresh(first))
        XCTAssertNil(OperationalTransitionDiagnostic.message(previous: first, current: second, previousPresentation: presentation, currentPresentation: presentation))
    }

    func testObservedOwnerChangeCreatesDiagnostic() {
        let first = evidence(date: Date(), source: .launch, duration: 1)
        var second = first
        second.keepAwake = .init(status: .unknown, summary: "missing")
        second.violations = [.keepAwakeNotVerified(.unknown)]
        let firstPresentation = OperationalSafetyPresentation.make(state: runtime(), availability: .fresh(first))
        let secondPresentation = OperationalSafetyPresentation.make(state: runtime(), availability: .fresh(second))
        XCTAssertNotNil(OperationalTransitionDiagnostic.message(previous: first, current: second, previousPresentation: firstPresentation, currentPresentation: secondPresentation))
    }

    func testConfirmToHeadlessUsesPreviousEvidenceModeAndOperationChangeIsMaterial() {
        var previous = evidence(date: Date(), source: .confirmCompletion, duration: 1)
        previous.runtimeMode = .confirmRequired
        let current = evidence(date: Date(), source: .confirmCompletion, duration: 1)
        let previousPresentation = OperationalSafetyPresentation.make(state: runtime(.confirmRequired), availability: .fresh(previous))
        let currentPresentation = OperationalSafetyPresentation.make(state: runtime(.headless), availability: .fresh(current))
        let message = OperationalTransitionDiagnostic.message(previous: previous, current: current, previousPresentation: previousPresentation, currentPresentation: currentPresentation)
        XCTAssertTrue(message?.contains("Awaiting confirmation->Managed Headless active") == true)

        var nextOperation = current
        nextOperation.operationID = "op-2"
        XCTAssertNotNil(OperationalTransitionDiagnostic.message(previous: current, current: nextOperation, previousPresentation: currentPresentation, currentPresentation: currentPresentation))
    }

    private func runtime(_ mode: HeadlessMode = .headless) -> RuntimeState {
        var state = RuntimeState.default
        state.mode = mode
        return state
    }

    private func evidence(date: Date, source: OperationalEvidenceSource, duration: Int) -> OperationalEvidence {
        .init(capturedAt: date, source: source, runtimeMode: .headless, operationID: "op", phase: .headlessActive,
              runtimeReadStatus: .success, journal: .activeConsistent(operationID: "op", stage: .headless),
              processSnapshot: .success(durationMilliseconds: duration),
              keepAwake: .init(status: .verifiedOwned, summary: "owned", pid: 42), virtualDisplay: .none,
              display: .init(expectedManagedDisplayID: nil, observedManagedDisplayID: nil, managedDisplayEnumerated: false, expectedDisplayMatchesObserved: nil, physicalMainDisplayID: 1, builtInPresent: false), violations: [])
    }
}
