import XCTest
@testable import CodexHeadlessCore

final class RestoreWorkflowTests: XCTestCase {
    func testNormalRestoreCleansUpOnlyAfterPhysicalTakeover() throws {
        let harness = try restoreHarness()

        let result = harness.controller.restoreNormal()

        XCTAssertEqual(result, .completed)
        let state = try harness.stateStore.read()
        XCTAssertEqual(state.mode, .normal)
        XCTAssertEqual(harness.virtual.destroyCallCount, 1)
        XCTAssertEqual(harness.sleep.disableCallCount, 1)
        XCTAssertTrue(harness.displays.display(id: 2)?.isMain == true)
    }

    func testTakeoverVerificationFailurePausesAndPreservesResources() throws {
        let harness = try restoreHarness()
        harness.displays.takeoverOverride = DisplayTakeoverVerification(
            displayID: 2, exists: true, physical: true, active: true, online: true, main: false, stable: true
        )

        let result = harness.controller.restoreNormal()

        guard case .pausedForSafety = result else { return XCTFail("Unexpected result: \(result)") }
        let state = try harness.stateStore.read()
        XCTAssertEqual(state.phase, .restorePaused)
        XCTAssertEqual(state.lastOutcome, .pausedForSafety)
        XCTAssertEqual(harness.virtual.destroyCallCount, 0)
        XCTAssertEqual(harness.sleep.disableCallCount, 0)
    }

    func testPhysicalDisplayDisappearsDuringStabilization() throws {
        let harness = try restoreHarness()
        harness.displays.takeoverOverride = DisplayTakeoverVerification(
            displayID: 2, exists: false, physical: false, active: false, online: false, main: false, stable: false
        )

        harness.controller.restoreNormal()

        XCTAssertEqual(try harness.stateStore.read().phase, .restorePaused)
        XCTAssertEqual(harness.virtual.destroyCallCount, 0)
    }

    func testMainPromotionFailurePausesRestore() throws {
        let harness = try restoreHarness()
        harness.displays.setMainError = FakeError.requested

        harness.controller.restoreNormal()

        XCTAssertEqual(try harness.stateStore.read().phase, .restorePaused)
        XCTAssertEqual(harness.virtual.destroyCallCount, 0)
    }

    func testPausedRestoreResumesWhenPhysicalDisplayAppears() throws {
        let harness = try restoreHarness()
        try harness.stateStore.transaction { state in
            state.mode = .restoring
            state.phase = .restorePaused
        }

        harness.controller.continuePausedRestoreIfReady()

        XCTAssertEqual(try harness.stateStore.read().mode, .normal)
        XCTAssertEqual(harness.virtual.destroyCallCount, 1)
    }

    func testStalePausedStateDoesNotRepeatCleanup() throws {
        let harness = try restoreHarness()
        try harness.stateStore.transaction { state in
            state.mode = .restoring
            state.phase = .restorePaused
        }
        harness.operationLock.onAcquire = { [weak harness] name in
            guard name == "resume-paused-restore", let harness else { return }
            try? harness.stateStore.transaction { state in
                state.mode = .normal
                state.phase = .idle
            }
        }

        harness.controller.continuePausedRestoreIfReady()

        XCTAssertEqual(harness.virtual.destroyCallCount, 0)
        XCTAssertEqual(harness.sleep.disableCallCount, 0)
    }

    func testCorruptedStateWithoutJournalDoesNotClaimSuccessEvenWithPhysicalDisplay() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        try Data("damaged".utf8).write(to: harness.directory.appendingPathComponent("state.json"))

        let result = harness.controller.restoreNormal()

        guard case .recoveryRequired = result else { return XCTFail("Unexpected result: \(result)") }
        XCTAssertEqual(try harness.stateStore.read().mode, .recoveryRequired)
    }

    func testCorruptedStateWithoutJournalRequiresRecoveryWithoutPhysicalDisplay() throws {
        let harness = try WorkflowHarness(displays: [])
        try Data("damaged".utf8).write(to: harness.directory.appendingPathComponent("state.json"))

        let result = harness.controller.restoreNormal()

        guard case .recoveryRequired = result else { return XCTFail("Unexpected result: \(result)") }
        XCTAssertEqual(try harness.stateStore.read().mode, .recoveryRequired)
        XCTAssertEqual(harness.virtual.destroyCallCount, 0)
    }

    func testVirtualCleanupFailureDoesNotWriteNormal() throws {
        let harness = try restoreHarness()
        harness.virtual.destroyResult = .ownershipMismatch(reason: "pid reused")

        let result = harness.controller.restoreNormal()

        guard case .cleanupIncomplete = result else { return XCTFail("Unexpected result: \(result)") }
        XCTAssertEqual(try harness.stateStore.read().phase, .restorePaused)
        XCTAssertEqual(harness.sleep.disableCallCount, 0)
    }

    func testKeepAwakeCleanupFailurePersistsProgress() throws {
        let harness = try restoreHarness()
        harness.sleep.disableResult = .failed(reason: "timeout")
        guard case .cleanupIncomplete(let progress, _) = harness.controller.restoreNormal() else {
            return XCTFail("Expected cleanupIncomplete")
        }
        XCTAssertEqual(progress.virtualDisplayCleanup, .completed)
        XCTAssertEqual(progress.keepAwakeCleanup, .failed)
        XCTAssertNotEqual(try harness.stateStore.read().mode, .normal)
    }

    func testFinalStateWriteFailureKeepsTruthInJournal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RestoreFinalWriteTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var initial = RuntimeState.default
        initial.mode = .headless
        initial.keepAwake = true
        initial.virtualDisplayCreated = true
        initial.virtualDisplayID = 9
        let stateStore = FailingStateStore(state: initial)
        stateStore.shouldFailTransaction = { $0.mode == .normal }
        let journal = RecoveryJournalStore(journalFile: directory.appendingPathComponent("journal.json"), lockFile: directory.appendingPathComponent("journal.lock"))
        _ = try journal.create(operationID: "final-write-test")
        try journal.update {
            $0.replacementDisplayID = 9
            $0.replacementDisplayType = "managedVirtual"
            $0.stage = .headless
        }
        let config = ConfigManager(configFile: directory.appendingPathComponent("config.json"), lockFile: directory.appendingPathComponent("config.lock"), healthFile: directory.appendingPathComponent("health.json"))
        try config.save(.default)
        let displays = FakeDisplayManager(displays: [
            makeDisplay(id: 2, builtIn: false, main: false),
            makeDisplay(id: 9, builtIn: false, managed: true, main: true)
        ])
        let controller = HeadlessController(
            configManager: config,
            stateStore: stateStore,
            recoveryJournalStore: journal,
            sleepManager: FakeSleepManager(),
            displayManager: displays,
            displayLayoutStore: FakeDisplayLayoutStore(),
            builtInDisplayManager: FakeBuiltInDisplayManager(),
            virtualDisplayManager: FakeVirtualDisplayManager(),
            touchBarManager: FakeTouchBarManager(),
            rollbackGuard: FakeRollbackGuard(),
            operationLock: FakeWorkflowOperationLock()
        )
        guard case .cleanupIncomplete(let progress, _) = controller.restoreNormal() else {
            return XCTFail("Expected cleanupIncomplete")
        }
        XCTAssertTrue(progress.physicalTakeoverVerified)
        XCTAssertEqual(progress.virtualDisplayCleanup, .completed)
        XCTAssertEqual(progress.keepAwakeCleanup, .completed)
        XCTAssertFalse(progress.finalStatePersisted)
        XCTAssertNotEqual(try stateStore.read().mode, .normal)
        XCTAssertNotNil(try journal.read())
    }

    func testDamagedConfigDoesNotBlockRestore() throws {
        let harness = try restoreHarness()
        try Data("damaged-config".utf8).write(to: harness.directory.appendingPathComponent("config.json"))
        XCTAssertEqual(harness.controller.restoreNormal(), .completed)
        XCTAssertEqual(try harness.stateStore.read().mode, .normal)
    }

    func testFutureConfigDoesNotBlockRestore() throws {
        let harness = try restoreHarness()
        try Data("{\"schemaVersion\":999}".utf8).write(to: harness.directory.appendingPathComponent("config.json"))
        XCTAssertEqual(harness.controller.restoreNormal(), .completed)
    }

    func testDamagedStateAndConfigRestoreBuiltInFromJournal() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 9, builtIn: false, managed: true, main: true)])
        let ownership = ManagedProcessOwnershipRecord(
            instanceID: "virtual-1",
            pid: 123,
            executableCanonicalPath: "/tmp/codex-headless",
            expectedCommandFragments: ["internal-helper", "virtual-display-host", "virtual-1"],
            ownerOperationID: "operation-1",
            resourceKind: "virtual-display",
            createdAt: Date()
        )
        _ = try harness.recoveryJournalStore.create(operationID: "operation-1")
        try harness.recoveryJournalStore.update { journal in
            journal.builtInDisplayID = 1
            journal.builtInSoftDisconnected = true
            journal.virtualDisplayHost = VirtualDisplayHostRecord(
                instanceID: "virtual-1",
                pid: 123,
                executablePath: "/tmp/codex-headless",
                startedAt: Date(),
                ownership: ownership
            )
            journal.replacementDisplayID = 9
            journal.replacementDisplayType = "managedVirtual"
            journal.stage = .headless
        }
        harness.builtIn.onRestoreDisplay = { [weak harness] in
            guard let harness else { return }
            for index in harness.displays.currentDisplays.indices { harness.displays.currentDisplays[index].isMain = false }
            harness.displays.currentDisplays.append(makeDisplay(id: 1, builtIn: true, main: true))
        }
        try Data("damaged-state".utf8).write(to: harness.directory.appendingPathComponent("state.json"))
        try Data("damaged-config".utf8).write(to: harness.directory.appendingPathComponent("config.json"))

        XCTAssertEqual(harness.controller.restoreNormal(), .completed)
        XCTAssertEqual(harness.builtIn.restoreDisplayCallCount, 1)
        XCTAssertNil(try harness.recoveryJournalStore.read())
        XCTAssertEqual(try harness.stateStore.read().mode, .normal)
    }

    func testDamagedStateWithoutJournalRequiresRecovery() throws {
        let harness = try WorkflowHarness(displays: [])
        try Data("damaged".utf8).write(to: harness.directory.appendingPathComponent("state.json"))
        guard case .recoveryRequired = harness.controller.restoreNormal() else {
            return XCTFail("Missing journal must require recovery")
        }
        XCTAssertEqual(try harness.stateStore.read().mode, .recoveryRequired)
    }

    private func restoreHarness() throws -> WorkflowHarness {
        var config = AppConfig.default
        var timing = TimingConfig.default
        timing.restoreBuiltInShortWaitSeconds = 0
        timing.restorePhysicalDisplayWaitSeconds = 0
        timing.restorePhysicalDisplayGraceSeconds = 0
        timing.restorePostPromoteStabilizationMilliseconds = 0
        config.timing = timing
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 2, builtIn: false, main: false),
            makeDisplay(id: 9, builtIn: false, managed: true, main: true)
        ], config: config)
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.virtualDisplayCreated = true
        state.virtualDisplayID = 9
        state.externalDisplayPromoted = true
        state.builtInBrightnessDimmed = true
        state.originalBrightness = 0.7
        try harness.stateStore.write(state)
        try harness.seedRecoveryJournal(for: state)
        return harness
    }
}
