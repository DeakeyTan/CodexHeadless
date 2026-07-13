import XCTest
@testable import CodexHeadlessCore

final class OperationalEvidenceAssessorTests: XCTestCase {
    func testHealthyHeadlessUsesOneSuppliedSnapshotAndDisplayEnumeration() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 2, builtIn: false, main: true)])
        var state = RuntimeState.default; state.mode = .headless; state.keepAwake = true; state.replacementDisplayID = 2; state.replacementDisplayType = "physical"
        try harness.stateStore.write(state); try harness.seedRecoveryJournal(for: state)
        try harness.recoveryJournalStore.update { $0.keepAwakeResource = .init(instanceID: "keep", resourceKind: "keep-awake", operationID: "test-operation", stage: .committed) }
        harness.sleep.observation = .init(status: .verifiedOwned, summary: "owned", pid: 2)
        let snapshot = ManagedProcessSnapshot(capturedAt: Date(), entries: [], succeeded: true, error: nil, durationMilliseconds: 4)
        let evidence = OperationalEvidenceAssessor(
            stateStore: harness.stateStore, journalStore: harness.recoveryJournalStore,
            sleepManager: harness.sleep, virtualManager: harness.virtual,
            displayManager: harness.displays,
            snapshotProvider: CountingSnapshotProvider(snapshot: .failed("must not be used"))
        ).assess(state: state, snapshot: snapshot, displays: harness.displays.displays(), source: .periodicReconcile)
        XCTAssertTrue(evidence.violations.isEmpty, String(describing: evidence.violations))
        XCTAssertEqual(harness.sleep.receivedSnapshots, [snapshot])
        XCTAssertEqual(harness.virtual.receivedSnapshots, [snapshot])
    }

    func testMissingJournalAndSnapshotFailureAreTyped() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        var state = RuntimeState.default; state.mode = .headless; state.keepAwake = true; try harness.stateStore.write(state)
        let evidence = OperationalEvidenceAssessor(
            stateStore: harness.stateStore, journalStore: harness.recoveryJournalStore,
            sleepManager: harness.sleep, virtualManager: harness.virtual, displayManager: harness.displays,
            snapshotProvider: CountingSnapshotProvider(snapshot: .failed("ps failed"))
        ).assess(source: .explicitDoctor)
        XCTAssertTrue(evidence.violations.contains(.journalMissing))
        XCTAssertTrue(evidence.violations.contains(.processSnapshotFailed("ps failed")))
    }

    func testMissingExactManagedDisplayIsStructuredNotTextParsed() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 12, builtIn: false, managed: true, main: true)])
        var state = RuntimeState.default; state.mode = .headless; state.keepAwake = true; state.virtualDisplayCreated = true; state.virtualDisplayID = 10; state.replacementDisplayID = 12
        try harness.stateStore.write(state); try harness.seedRecoveryJournal(for: state)
        try harness.recoveryJournalStore.update {
            $0.keepAwakeResource = .init(instanceID: "keep", resourceKind: "keep-awake", operationID: "test-operation", stage: .committed)
            $0.virtualDisplayResource = .init(instanceID: "virtual", resourceKind: "virtual-display", operationID: "test-operation", stage: .committed, displayID: 10)
        }
        harness.sleep.observation = .init(status: .verifiedOwned, summary: "owned")
        harness.virtual.observation = .init(status: .verifiedOwned, summary: "owned")
        let evidence = OperationalEvidenceAssessor(
            stateStore: harness.stateStore, journalStore: harness.recoveryJournalStore,
            sleepManager: harness.sleep, virtualManager: harness.virtual, displayManager: harness.displays,
            snapshotProvider: CountingSnapshotProvider(snapshot: .init(capturedAt: Date(), entries: [], succeeded: true, error: nil, durationMilliseconds: 1))
        ).assess(source: .explicitStatus)
        XCTAssertTrue(evidence.violations.contains(.managedDisplayMissing(10)))
        XCTAssertEqual(evidence.display.observedManagedDisplayID, nil)
    }

    func testConfirmRequiredValidatesReplacementAndRollbackState() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        var state = RuntimeState.default
        state.mode = .confirmRequired
        state.keepAwake = true
        try harness.stateStore.write(state)
        try harness.seedRecoveryJournal(for: state, stage: .headless)
        try harness.recoveryJournalStore.update {
            $0.keepAwakeResource = .init(instanceID: "keep", resourceKind: "keep-awake", operationID: "test-operation", stage: .committed)
        }
        harness.sleep.observation = .init(status: .verifiedOwned, summary: "owned")
        let evidence = assessor(harness).assess(source: .explicitStatus)
        XCTAssertTrue(evidence.violations.contains(.replacementDisplayMissing(nil)))
        XCTAssertTrue(evidence.violations.contains { if case .confirmationStateMismatch = $0 { true } else { false } })
    }

    func testPreparingRequiresKeepAwakeOnlyAfterJournalStageCommitsIt() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        var state = RuntimeState.default
        state.mode = .preparing
        try harness.stateStore.write(state)
        try harness.seedRecoveryJournal(for: state, stage: .enabling)
        var evidence = assessor(harness).assess(source: .periodicReconcile)
        XCTAssertFalse(evidence.violations.contains { if case .keepAwakeNotVerified = $0 { true } else { false } })
        try harness.recoveryJournalStore.update { $0.stage = .keepAwakeStarted }
        evidence = assessor(harness).assess(source: .periodicReconcile)
        XCTAssertTrue(evidence.violations.contains(.keepAwakeNotVerified(.none)))
    }

    func testHeadlessSoftDisconnectMustAgreeWithDisplayEnumeration() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: false), makeDisplay(id: 2, builtIn: false, main: true)])
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.builtInSoftDisconnected = true
        state.replacementDisplayID = 2
        try harness.stateStore.write(state)
        try harness.seedRecoveryJournal(for: state)
        try harness.recoveryJournalStore.update {
            $0.keepAwakeResource = .init(instanceID: "keep", resourceKind: "keep-awake", operationID: "test-operation", stage: .committed)
        }
        harness.sleep.observation = .init(status: .verifiedOwned, summary: "owned")
        let evidence = assessor(harness).assess(source: .explicitDoctor)
        XCTAssertTrue(evidence.violations.contains { if case .builtInStateMismatch = $0 { true } else { false } })
    }

    func testHeadlessStateRequiresKeepAwakeEvenWhenOwnerExists() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 2, builtIn: false, main: true)])
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = false
        state.replacementDisplayID = 2
        try harness.stateStore.write(state)
        try harness.seedRecoveryJournal(for: state)
        try harness.recoveryJournalStore.update {
            $0.keepAwakeResource = .init(instanceID: "keep", resourceKind: "keep-awake", operationID: "test-operation", stage: .committed)
        }
        harness.sleep.observation = .init(status: .verifiedOwned, summary: "owned")
        let evidence = assessor(harness).assess(source: .periodicReconcile)
        XCTAssertTrue(evidence.violations.contains(.keepAwakeStateMismatch))
    }

    func testExactManagedDisplayWinsWhenAnotherManagedDisplayAppearsFirst() throws {
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 11, builtIn: false, managed: true, main: false),
            makeDisplay(id: 12, builtIn: false, managed: true, main: true)
        ])
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.virtualDisplayCreated = true
        state.virtualDisplayID = 12
        state.replacementDisplayID = 12
        try harness.stateStore.write(state)
        try harness.seedRecoveryJournal(for: state)
        try harness.recoveryJournalStore.update {
            $0.keepAwakeResource = .init(instanceID: "keep", resourceKind: "keep-awake", operationID: "test-operation", stage: .committed)
            $0.virtualDisplayResource = .init(instanceID: "virtual", resourceKind: "virtual-display", operationID: "test-operation", stage: .committed, displayID: 12)
        }
        harness.sleep.observation = .init(status: .verifiedOwned, summary: "owned")
        harness.virtual.observation = .init(status: .verifiedOwned, summary: "owned")
        let evidence = assessor(harness).assess(source: .periodicReconcile)
        XCTAssertEqual(evidence.display.observedManagedDisplayID, 12)
        XCTAssertTrue(evidence.display.replacementDisplayEnumerated)
        XCTAssertTrue(evidence.display.replacementDisplayManagedVirtual)
        XCTAssertFalse(evidence.violations.contains { if case .managedDisplayIDMismatch = $0 { true } else { false } })
    }

    func testPhysicalReplacementUsesExactIDAndRecordsUsability() throws {
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 2, builtIn: false, main: false),
            makeDisplay(id: 3, builtIn: false, main: true)
        ])
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.replacementDisplayID = 2
        try harness.stateStore.write(state)
        try harness.seedRecoveryJournal(for: state)
        try harness.recoveryJournalStore.update {
            $0.keepAwakeResource = .init(instanceID: "keep", resourceKind: "keep-awake", operationID: "test-operation", stage: .committed)
        }
        harness.sleep.observation = .init(status: .verifiedOwned, summary: "owned")
        let evidence = assessor(harness).assess(source: .periodicReconcile)
        XCTAssertEqual(evidence.display.expectedReplacementDisplayID, 2)
        XCTAssertTrue(evidence.display.replacementDisplayEnumerated)
        XCTAssertTrue(evidence.display.replacementDisplayActive)
        XCTAssertTrue(evidence.display.replacementDisplayOnline)
        XCTAssertFalse(evidence.display.replacementDisplayMain)
        XCTAssertFalse(evidence.display.replacementDisplayManagedVirtual)
    }

    private func assessor(_ harness: WorkflowHarness) -> OperationalEvidenceAssessor {
        OperationalEvidenceAssessor(
            stateStore: harness.stateStore, journalStore: harness.recoveryJournalStore,
            sleepManager: harness.sleep, virtualManager: harness.virtual, displayManager: harness.displays,
            snapshotProvider: CountingSnapshotProvider(snapshot: .init(capturedAt: Date(), entries: [], succeeded: true, error: nil, durationMilliseconds: 1))
        )
    }
}
