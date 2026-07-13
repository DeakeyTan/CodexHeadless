import XCTest
@testable import CodexHeadlessCore

final class CleanNormalClassificationTests: XCTestCase {
    func testSleepingPhysicalMainIsTemporaryNotDirty() throws {
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 1, builtIn: true, main: true, active: false, online: true)
        ])
        let assessment = CleanNormalAssessor(
            stateStore: harness.stateStore,
            recoveryJournalStore: harness.recoveryJournalStore,
            sleepManager: harness.sleep,
            virtualDisplayManager: harness.virtual,
            displayManager: harness.displays,
            snapshotProvider: CountingSnapshotProvider(snapshot: ManagedProcessSnapshot(
                capturedAt: Date(), entries: [], succeeded: true, error: nil, durationMilliseconds: 1
            ))
        ).assess()
        XCTAssertEqual(assessment.classification, .temporarilyUnavailable)
        XCTAssertFalse(assessment.recommendedAction.contains("Restore"))
    }

    func testClassificationMatrix() {
        XCTAssertEqual(assessment().classification, .clean)
        XCTAssertEqual(assessment(runtime: ["owner remains"]).classification, .resourceDirty)
        XCTAssertEqual(assessment(journal: "active").classification, .recoveryRequired)
        XCTAssertEqual(assessment(snapshotSucceeded: false).classification, .unknown)
        XCTAssertEqual(assessment(physicalUnavailable: true).classification, .temporarilyUnavailable)
    }

    func testTemporaryDisplayConditionDoesNotRecommendRestore() {
        let value = assessment(physicalUnavailable: true)
        XCTAssertFalse(value.isClean)
        XCTAssertTrue(value.recommendedAction.contains("Wake"))
        XCTAssertFalse(value.recommendedAction.contains("Restore"))
    }

    func testTransitionDiagnosticContainsBoundedEvidenceAndDeduplicates() {
        let clean = assessment()
        let unavailable = assessment(physicalUnavailable: true)
        let message = CleanNormalTransitionDiagnostic.message(
            previous: clean, current: unavailable, source: "periodic-normal", durationMilliseconds: 12
        )
        XCTAssertTrue(message?.contains("clean->temporarilyUnavailable") == true)
        XCTAssertTrue(message?.contains("snapshot=success") == true)
        XCTAssertNil(CleanNormalTransitionDiagnostic.message(
            previous: unavailable, current: unavailable, source: "periodic-normal", durationMilliseconds: 13
        ))
    }

    private func assessment(
        runtime: [String] = [],
        journal: String? = nil,
        snapshotSucceeded: Bool = true,
        physicalUnavailable: Bool = false
    ) -> CleanNormalAssessment {
        CleanNormalAssessment(
            runtimeViolations: runtime, journalViolation: journal,
            observedResourceViolations: [],
            displayViolations: physicalUnavailable ? ["display inactive"] : [],
            keepAwakeObservation: .none, virtualDisplayObservation: .none,
            journalReadSucceeded: true, processSnapshotSucceeded: snapshotSucceeded,
            processSnapshotError: snapshotSucceeded ? nil : "ps failed",
            physicalDisplayTemporarilyUnavailable: physicalUnavailable
        )
    }
}
