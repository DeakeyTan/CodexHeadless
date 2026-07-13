import Foundation
import XCTest
@testable import CodexHeadlessCore

final class StatePersistenceSafetyTests: XCTestCase {
    func testSoftDisconnectPersistenceFailureTriggersPhysicalRecovery() throws {
        var config = AppConfig.default
        config.softDisconnectBuiltInDisplay = true
        let context = try makeContext(
            state: .default,
            config: config,
            displays: [
                makeDisplay(id: 1, builtIn: true, main: true),
                makeDisplay(id: 2, builtIn: false, main: false)
            ]
        )
        defer { context.cleanup() }
        context.builtIn.softDisconnectResult = .succeeded(method: "fake", message: "disconnected")
        context.stateStore.shouldFailTransaction = { state in state.builtInSoftDisconnected == true }

        XCTAssertThrowsError(try context.controller.enableHeadless())

        XCTAssertTrue(context.displays.display(id: 1)?.isMain == true)
        XCTAssertEqual(context.virtual.destroyCallCount, 1)
        XCTAssertEqual(context.sleep.disableCallCount, 1)
        XCTAssertEqual(try context.stateStore.read().mode, .normal)
    }

    func testRestorePausedPersistenceFailureStillPreservesVirtualAndKeepAwake() throws {
        var config = AppConfig.default
        var timing = TimingConfig.default
        timing.restorePhysicalDisplayWaitSeconds = 0
        timing.restorePhysicalDisplayGraceSeconds = 0
        timing.restorePostPromoteStabilizationMilliseconds = 0
        config.timing = timing
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        state.virtualDisplayCreated = true
        state.virtualDisplayID = 9
        let context = try makeContext(
            state: state,
            config: config,
            displays: [
                makeDisplay(id: 2, builtIn: false, main: false),
                makeDisplay(id: 9, builtIn: false, managed: true, main: true)
            ]
        )
        defer { context.cleanup() }
        context.displays.takeoverOverride = DisplayTakeoverVerification(
            displayID: 2, exists: true, physical: true, active: true, online: true, main: false, stable: true
        )
        context.stateStore.shouldFailTransaction = { state in state.phase == .restorePaused }

        context.controller.restoreNormal()

        XCTAssertEqual(context.virtual.destroyCallCount, 0)
        XCTAssertEqual(context.sleep.disableCallCount, 0)
        XCTAssertTrue(try context.stateStore.read().virtualDisplayCreated)
    }

    private func makeContext(
        state: RuntimeState,
        config: AppConfig,
        displays initialDisplays: [DisplayInfo]
    ) throws -> PersistenceContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHeadless-PersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configManager = ConfigManager(
            configFile: directory.appendingPathComponent("config.json"),
            lockFile: directory.appendingPathComponent("config.lock"),
            healthFile: directory.appendingPathComponent("config.health.json")
        )
        try configManager.save(config)
        let stateStore = FailingStateStore(state: state)
        let displays = FakeDisplayManager(displays: initialDisplays)
        let virtual = FakeVirtualDisplayManager()
        let builtIn = FakeBuiltInDisplayManager()
        let sleep = FakeSleepManager()
        let controller = HeadlessController(
            configManager: configManager,
            stateStore: stateStore,
            sleepManager: sleep,
            displayManager: displays,
            displayLayoutStore: FakeDisplayLayoutStore(),
            builtInDisplayManager: builtIn,
            virtualDisplayManager: virtual,
            touchBarManager: FakeTouchBarManager(),
            rollbackGuard: FakeRollbackGuard(),
            operationLock: FakeWorkflowOperationLock()
        )
        return PersistenceContext(
            directory: directory,
            stateStore: stateStore,
            displays: displays,
            virtual: virtual,
            builtIn: builtIn,
            sleep: sleep,
            controller: controller
        )
    }
}

private struct PersistenceContext {
    let directory: URL
    let stateStore: FailingStateStore
    let displays: FakeDisplayManager
    let virtual: FakeVirtualDisplayManager
    let builtIn: FakeBuiltInDisplayManager
    let sleep: FakeSleepManager
    let controller: HeadlessController
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
