import XCTest
@testable import CodexHeadlessCore

final class EnableWorkflowTests: XCTestCase {
    func testExternalDisplayEnableDoesNotCreateVirtualDisplay() throws {
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 1, builtIn: true, main: true),
            makeDisplay(id: 2, builtIn: false, main: false)
        ])
        harness.builtIn.brightness = 0.7

        try harness.controller.enableHeadless()

        let state = try harness.stateStore.read()
        XCTAssertEqual(state.mode, .headless)
        XCTAssertEqual(state.replacementDisplayType, "external")
        XCTAssertEqual(harness.virtual.createCallCount, 0)
        XCTAssertEqual(harness.sleep.enableCallCount, 1)
        XCTAssertTrue(harness.displays.display(id: 2)?.isMain == true)
    }

    func testSoftwareVirtualDisplayEnableRequiresConfirmation() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        harness.builtIn.brightness = 0.7
        harness.virtual.createResult = 9
        harness.virtual.onCreate = { [weak harness] id in
            harness?.displays.currentDisplays.append(makeDisplay(id: id, builtIn: false, managed: true, main: false))
        }

        try harness.controller.enableHeadless()

        let state = try harness.stateStore.read()
        XCTAssertEqual(state.mode, .confirmRequired)
        XCTAssertEqual(state.virtualDisplayID, 9)
        XCTAssertEqual(state.replacementDisplayType, "managedVirtual")
        XCTAssertTrue(state.confirmationRequired == true)
    }

    func testVirtualDisplayCreationFailureCleansOnlyPreparedResources() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        harness.builtIn.brightness = 0.7
        harness.virtual.createError = FakeError.requested

        XCTAssertThrowsError(try harness.controller.enableHeadless()) { error in
            XCTAssertTrue(error.localizedDescription.contains("requested"))
        }

        let state = try harness.stateStore.read()
        XCTAssertEqual(state.mode, .normal)
        XCTAssertEqual(state.lastOutcome, .recoveredWithWarning)
        XCTAssertTrue(harness.displays.display(id: 1)?.isMain == true)
        XCTAssertEqual(harness.virtual.destroyCallCount, 1)
        XCTAssertEqual(harness.sleep.disableCallCount, 1)
    }

    func testPromotionFailureRecoversPhysicalDisplayBeforeCleanup() throws {
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 1, builtIn: true, main: true),
            makeDisplay(id: 2, builtIn: false, main: false)
        ])
        harness.builtIn.brightness = 0.7
        harness.displays.setMainResult = false

        XCTAssertThrowsError(try harness.controller.enableHeadless())

        let state = try harness.stateStore.read()
        XCTAssertEqual(state.mode, .normal)
        XCTAssertEqual(harness.virtual.destroyCallCount, 1)
        XCTAssertEqual(harness.sleep.disableCallCount, 1)
    }

    func testSoftDisconnectFailureUsesVerifiedRecovery() throws {
        var config = AppConfig.default
        config.softDisconnectBuiltInDisplay = true
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 1, builtIn: true, main: true),
            makeDisplay(id: 2, builtIn: false, main: false)
        ], config: config)
        harness.builtIn.softDisconnectResult = .failed("private API unavailable")

        XCTAssertThrowsError(try harness.controller.enableHeadless())

        XCTAssertEqual(try harness.stateStore.read().mode, .normal)
        XCTAssertTrue(harness.displays.display(id: 1)?.isMain == true)
        XCTAssertEqual(harness.sleep.disableCallCount, 1)
    }

    func testFailedRecoveryKeepsReplacementAndKeepAwake() throws {
        var config = AppConfig.default
        config.softDisconnectBuiltInDisplay = true
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 1, builtIn: true, main: true),
            makeDisplay(id: 2, builtIn: false, main: false)
        ], config: config)
        harness.builtIn.softDisconnectResult = .failed("failure")
        harness.displays.takeoverOverride = DisplayTakeoverVerification(
            displayID: 1, exists: true, physical: true, active: true, online: true, main: false, stable: true
        )

        XCTAssertThrowsError(try harness.controller.enableHeadless())

        let state = try harness.stateStore.read()
        XCTAssertEqual(state.mode, .restoring)
        XCTAssertEqual(state.phase, .restorePaused)
        XCTAssertEqual(state.lastOutcome, .pausedForSafety)
        XCTAssertEqual(harness.virtual.destroyCallCount, 0)
        XCTAssertEqual(harness.sleep.disableCallCount, 0)
    }

    func testEnableCancellationBeforeCommit() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
        harness.builtIn.brightness = 0.7
        harness.virtual.createResult = 9
        harness.virtual.onCreate = { [weak harness] id in
            guard let harness else { return }
            harness.displays.currentDisplays.append(makeDisplay(id: id, builtIn: false, managed: true, main: false))
            try harness.stateStore.transaction { $0.enableCancellationRequested = true }
        }

        XCTAssertThrowsError(try harness.controller.enableHeadless())
        XCTAssertEqual(try harness.stateStore.read().mode, .normal)
        XCTAssertEqual(harness.displays.setMainCallCount, 0)
    }

    func testHeadlessEnableIsRejectedByCoreModeGate() throws {
        let harness = try WorkflowHarness(displays: [makeDisplay(id: 2, builtIn: false, main: true)])
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.externalDisplayPromoted = true
        state.builtInBrightnessDimmed = true
        try harness.stateStore.write(state)

        XCTAssertThrowsError(try harness.controller.enableHeadless())

        XCTAssertEqual(harness.sleep.enableCallCount, 0)
        XCTAssertEqual(harness.virtual.createCallCount, 0)
    }

    func testEveryNonNormalModeIsRejected() throws {
        let modes: [HeadlessMode] = [.preparing, .confirmRequired, .headless, .fallback, .restoring, .error, .recoveryRequired]
        for mode in modes {
            let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)])
            var state = RuntimeState.default
            state.mode = mode
            try harness.stateStore.write(state)
            XCTAssertThrowsError(try harness.controller.enableHeadless(), "mode=\(mode.rawValue)")
            XCTAssertEqual(harness.sleep.enableCallCount, 0)
        }
    }

    func testBrightnessCapabilityFailureStopsBeforePreparing() throws {
        let harness = try WorkflowHarness(displays: [
            makeDisplay(id: 1, builtIn: true, main: true),
            makeDisplay(id: 2, builtIn: false, main: false)
        ])
        harness.builtIn.capability = BrightnessCapability(available: false, method: nil, guidance: "grant Accessibility")
        XCTAssertThrowsError(try harness.controller.enableHeadless())
        XCTAssertEqual(try harness.stateStore.read().mode, .normal)
        XCTAssertNil(try harness.recoveryJournalStore.read())
        XCTAssertEqual(harness.sleep.enableCallCount, 0)
    }

    func testAllEnablePersistenceFailurePointsAvoidFalseHeadless() throws {
        for point in EnableFailurePoint.allCases {
            var config = AppConfig.default
            config.softDisconnectBuiltInDisplay = point != .brightnessDimmed
            config.hideTouchBarInHeadless = true
            let harness = try WorkflowHarness(displays: [makeDisplay(id: 1, builtIn: true, main: true)], config: config)
            if config.softDisconnectBuiltInDisplay != true { harness.builtIn.brightness = 0.7 }
            harness.virtual.createResult = 9
            harness.virtual.onCreate = { [weak harness] id in
                harness?.displays.currentDisplays.append(makeDisplay(id: id, builtIn: false, managed: true, main: false))
            }
            harness.virtual.onDestroy = { [weak harness] in
                harness?.displays.currentDisplays.removeAll { $0.isManagedVirtual }
            }
            harness.builtIn.softDisconnectResult = point == .brightnessDimmed
                ? .failed("disabled")
                : .succeeded(method: "fake", message: "disconnected")
            let injector = FakeWorkflowFailureInjector()
            injector.failingPoint = point
            let controller = HeadlessController(
                configManager: harness.configManager,
                stateStore: harness.stateStore,
                recoveryJournalStore: harness.recoveryJournalStore,
                sleepManager: harness.sleep,
                displayManager: harness.displays,
                displayLayoutStore: harness.layout,
                builtInDisplayManager: harness.builtIn,
                virtualDisplayManager: harness.virtual,
                touchBarManager: harness.touchBar,
                rollbackGuard: harness.rollback,
                operationLock: harness.operationLock,
                failureInjector: injector
            )
            XCTAssertThrowsError(try controller.enableHeadless(), "point=\(point.rawValue)")
            let state = try harness.stateStore.read()
            XCTAssertFalse(state.mode == .headless || state.mode == .confirmRequired, "point=\(point.rawValue)")
            if state.mode == .normal { XCTAssertNil(try harness.recoveryJournalStore.read()) }
        }
    }
}
