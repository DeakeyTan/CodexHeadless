import Foundation
@testable import CodexHeadlessCore

final class FakeDisplayManager: DisplayManaging {
    var currentDisplays: [DisplayInfo]
    var setMainError: Error?
    var setMainResult = true
    var takeoverOverride: DisplayTakeoverVerification?
    var setMainCallCount = 0
    var restoreLayoutCallCount = 0

    init(displays: [DisplayInfo]) { currentDisplays = displays }

    func displays() -> [DisplayInfo] { currentDisplays }
    func hasAlternativeDisplay() -> Bool { preferredExternalDisplay() != nil }
    func preferredExternalDisplay() -> DisplayInfo? {
        currentDisplays.first { !$0.isBuiltIn && !$0.isManagedVirtual && $0.isActive && $0.isOnline }
    }
    func display(id: UInt32) -> DisplayInfo? { currentDisplays.first { $0.id == id } }
    func waitForDisplay(id: UInt32, present expectedPresent: Bool, timeoutSeconds: TimeInterval) -> Bool {
        currentDisplays.contains { $0.id == id } == expectedPresent
    }
    func setMainDisplayToRestorePriority(managedVirtualDisplayID: UInt32?) throws {
        guard let display = restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID) else { return }
        _ = try setMainDisplay(id: display.id, reason: "restore", fallbackResolution: nil)
    }
    func restorePriorityDisplay(managedVirtualDisplayID: UInt32?) -> DisplayInfo? {
        currentDisplays.first { !$0.isBuiltIn && !$0.isManagedVirtual && $0.id != managedVirtualDisplayID && $0.isActive }
            ?? currentDisplays.first { $0.isBuiltIn && $0.isActive }
    }
    func waitForRestorePriorityDisplay(managedVirtualDisplayID: UInt32?, timeoutSeconds: TimeInterval) -> DisplayInfo? {
        restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID)
    }
    func setMainDisplay(id targetID: UInt32, reason: String, fallbackResolution: Resolution?) throws -> Bool {
        setMainCallCount += 1
        if let setMainError { throw setMainError }
        guard setMainResult, currentDisplays.contains(where: { $0.id == targetID }) else { return false }
        for index in currentDisplays.indices { currentDisplays[index].isMain = currentDisplays[index].id == targetID }
        return true
    }
    func restoreLayout(from snapshot: DisplayLayoutSnapshot, managedVirtualDisplayID: UInt32?) throws -> DisplayLayoutRestoreResult {
        restoreLayoutCallCount += 1
        return DisplayLayoutRestoreResult(appliedCount: 1, skippedCount: 0, message: "fake layout restored")
    }
    func compactStatus(displays: [DisplayInfo]?) -> String { "fake displays" }
    func statusLines(managedVirtualDisplayID: UInt32?) -> [String] { [] }
    func verifyPhysicalTakeover(displayID: UInt32, managedVirtualDisplayID: UInt32?, stabilizationSeconds: TimeInterval) -> DisplayTakeoverVerification {
        if let takeoverOverride { return takeoverOverride }
        let display = currentDisplays.first { $0.id == displayID }
        return DisplayTakeoverVerification(
            displayID: displayID,
            exists: display != nil,
            physical: display?.isManagedVirtual == false && display?.id != managedVirtualDisplayID,
            active: display?.isActive == true,
            online: display?.isOnline == true,
            main: display?.isMain == true,
            stable: display != nil
        )
    }
}

final class FakeVirtualDisplayManager: VirtualDisplayManaging {
    var createResult: UInt32?
    var createError: Error?
    var createCallCount = 0
    var destroyCallCount = 0
    var reconcileCallCount = 0
    var onCreate: ((UInt32) throws -> Void)?
    var onDestroy: (() -> Void)?
    var observation: ManagedResourceObservation = .none
    var receivedSnapshots: [ManagedProcessSnapshot?] = []

    func validateResolution(_ resolution: Resolution) throws { try ResolutionManager.validate(resolution) }
    func createVirtualDisplay(resolution: Resolution, refreshRate: Int, scaleMode: String, waitTimeoutSeconds: TimeInterval, reportedIDExtraWaitSeconds: TimeInterval) throws -> UInt32? {
        createCallCount += 1
        if let createError { throw createError }
        if let id = createResult { try onCreate?(id) }
        return createResult
    }
    var destroyResult: ManagedResourceCleanupResult = .stopped
    func destroyVirtualDisplayIfManaged() -> ManagedResourceCleanupResult {
        destroyCallCount += 1
        if destroyResult.completed { onDestroy?() }
        return destroyResult
    }
    func reconcileManagedVirtualDisplayIfNeeded() { reconcileCallCount += 1 }
    func reconcileManagedVirtualDisplayIfNeeded(displays: [DisplayInfo]) { reconcileCallCount += 1 }
    func recoveryHostRecord() -> VirtualDisplayHostRecord? { nil }
    func managedResourceObservation(snapshot: ManagedProcessSnapshot?) -> ManagedResourceObservation {
        receivedSnapshots.append(snapshot)
        return observation
    }
}

final class FakeBuiltInDisplayManager: BuiltInDisplayManaging {
    var brightness: Float?
    var dimResult = BrightnessChangeResult.succeeded(method: "fake", message: "dimmed")
    var softDisconnectResult = SoftDisconnectResult.failed("disabled")
    var restoreDisplayResult = SoftDisconnectResult.succeeded(method: "fake", message: "restored")
    var dimCallCount = 0
    var restoreBrightnessCallCount = 0
    var restoredBrightnessValues: [Float?] = []
    var restoreBrightnessResult = BrightnessChangeResult.succeeded(method: "fake", message: "brightness restored")
    var restoreDisplayCallCount = 0
    var onRestoreDisplay: (() -> Void)?

    func currentBrightness() -> Float? { brightness }
    var capability = BrightnessCapability(available: true, method: "fake", guidance: "available")
    func brightnessCapability() -> BrightnessCapability { capability }
    func dimBuiltInDisplay() -> BrightnessChangeResult { dimCallCount += 1; return dimResult }
    func restoreBrightness(_ brightness: Float?) -> BrightnessChangeResult {
        restoreBrightnessCallCount += 1
        restoredBrightnessValues.append(brightness)
        return restoreBrightnessResult
    }
    func attemptSoftDisconnectIfSafe(builtInDisplayID: UInt32?, hasAlternativeDisplay: Bool, enabled: Bool) -> SoftDisconnectResult {
        softDisconnectResult
    }
    func restoreBuiltInDisplay(displayID: UInt32?) -> SoftDisconnectResult {
        restoreDisplayCallCount += 1
        onRestoreDisplay?()
        return restoreDisplayResult
    }
}

final class FakeSleepManager: SleepManaging {
    var enableCallCount = 0
    var disableCallCount = 0
    var syncCallCount = 0
    var enableError: Error?
    var observation: ManagedResourceObservation = .none
    var receivedSnapshots: [ManagedProcessSnapshot?] = []
    func enableKeepAwake() throws { enableCallCount += 1; if let enableError { throw enableError } }
    var disableResult: ManagedResourceCleanupResult = .stopped
    func disableKeepAwake() -> ManagedResourceCleanupResult { disableCallCount += 1; return disableResult }
    func syncWithState() { syncCallCount += 1 }
    func applyDisplaySleepFast() {}
    func recoveryHostRecord() -> KeepAwakeHostRecord? { nil }
    func managedResourceObservation(snapshot: ManagedProcessSnapshot?) -> ManagedResourceObservation {
        receivedSnapshots.append(snapshot)
        return observation
    }
}

final class FakeTouchBarManager: TouchBarManaging {
    var hideCallCount = 0
    var showCallCount = 0
    var showResult = TouchBarChangeResult.succeeded(method: "fake", message: "shown")
    func hideIfEnabled(_ enabled: Bool) -> TouchBarChangeResult {
        hideCallCount += 1
        return enabled ? .succeeded(method: "fake", message: "hidden") : .skipped("disabled")
    }
    func showIfNeeded(_ wasHidden: Bool?) -> TouchBarChangeResult {
        showCallCount += 1
        return showResult
    }
}

final class FakeRollbackGuard: RollbackDeadlineClearing {
    var deadline: Date?
    func begin(timeoutSeconds: Int) throws -> Date { let value = Date().addingTimeInterval(Double(timeoutSeconds)); deadline = value; return value }
    func confirm() throws { deadline = nil }
    func cancel() throws { deadline = nil }
    func needsRollback(now: Date) -> Bool { deadline.map { now >= $0 } ?? false }
}

final class FakeDisplayLayoutStore: DisplayLayoutStoring {
    var saveCallCount = 0
    func loadMatching(displays: [DisplayInfo]) throws -> DisplayLayoutSnapshot {
        DisplayLayoutSnapshot(version: 1, profileKey: "fake", createdAt: Date(), reason: "fake", displays: [])
    }
    func saveCurrentLayout(displayManager: DisplayManaging, reason: String, includeManagedVirtual: Bool) { saveCallCount += 1 }
}

final class FakeWorkflowLease: WorkflowOperationLeaseHandling {
    let operationID = "test-operation"
    func release() {}
}

final class FakeWorkflowOperationLock: WorkflowOperationLocking {
    var acquisitions: [String] = []
    var onAcquire: ((String) -> Void)?
    func acquire(name: String, timeoutSeconds: TimeInterval, logLifecycle: Bool) throws -> WorkflowOperationLeaseHandling {
        acquisitions.append(name)
        onAcquire?(name)
        return FakeWorkflowLease()
    }
}

enum FakeError: LocalizedError {
    case requested
    var errorDescription: String? { "Fake requested failure" }
}

final class FakeWorkflowClock: WorkflowClock {
    var now = Date(timeIntervalSince1970: 1_000)
    var uptime: TimeInterval = 1_000
    var onSleep: ((TimeInterval) -> Void)?
    func sleep(seconds: TimeInterval) {
        uptime += seconds
        now = now.addingTimeInterval(seconds)
        onSleep?(seconds)
    }
}

final class FakeWorkflowFailureInjector: WorkflowFailureInjecting {
    var failingPoint: EnableFailurePoint?
    func check(_ point: EnableFailurePoint) throws {
        if point == failingPoint { throw FakeError.requested }
    }
}

final class FailingStateStore: RuntimeStateStoring {
    private let lock = NSLock()
    private var state: RuntimeState
    var shouldFailTransaction: ((RuntimeState) -> Bool)?

    init(state: RuntimeState = .default) { self.state = state }

    func load() -> RuntimeState { (try? read()) ?? .recoveryRequired(message: "fake read failure") }
    func save(_ state: RuntimeState) throws { try write(state) }
    func read() throws -> RuntimeState {
        lock.lock(); defer { lock.unlock() }
        return state
    }
    func write(_ state: RuntimeState) throws {
        lock.lock(); defer { lock.unlock() }
        self.state = state
    }
    func replaceCorruptedStateAfterVerifiedRecovery(_ state: RuntimeState) throws { try write(state) }
    func transaction<T>(_ mutation: (inout RuntimeState) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        var candidate = state
        let result = try mutation(&candidate)
        if shouldFailTransaction?(candidate) == true { throw FakeError.requested }
        state = candidate
        return result
    }
    func bestEffortUpdate(_ mutation: (inout RuntimeState) -> Void) {
        lock.lock(); defer { lock.unlock() }
        mutation(&state)
    }
}

func makeDisplay(id: UInt32, builtIn: Bool, managed: Bool = false, main: Bool, active: Bool = true, online: Bool = true) -> DisplayInfo {
    DisplayInfo(
        id: id,
        isMain: main,
        isBuiltIn: builtIn,
        isActive: active,
        isOnline: online,
        width: 1920,
        height: 1080,
        originX: main ? 0 : 1920,
        originY: 0,
        vendorNumber: managed ? 0xC0DE : 1,
        modelNumber: managed ? 0x0511 : id
    )
}

final class WorkflowHarness {
    let directory: URL
    let stateStore: StateStore
    let configManager: ConfigManager
    let recoveryJournalStore: RecoveryJournalStore
    let displays: FakeDisplayManager
    let virtual: FakeVirtualDisplayManager
    let builtIn: FakeBuiltInDisplayManager
    let sleep: FakeSleepManager
    let touchBar: FakeTouchBarManager
    let rollback: FakeRollbackGuard
    let layout: FakeDisplayLayoutStore
    let operationLock: FakeWorkflowOperationLock
    lazy var controller = HeadlessController(
        configManager: configManager,
        stateStore: stateStore,
        recoveryJournalStore: recoveryJournalStore,
        sleepManager: sleep,
        displayManager: displays,
        displayLayoutStore: layout,
        builtInDisplayManager: builtIn,
        virtualDisplayManager: virtual,
        touchBarManager: touchBar,
        rollbackGuard: rollback,
        operationLock: operationLock
    )

    init(displays initialDisplays: [DisplayInfo], config: AppConfig = .default) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHeadless-WorkflowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateStore = StateStore(
            stateFile: directory.appendingPathComponent("state.json"),
            lockFile: directory.appendingPathComponent("state.lock")
        )
        configManager = ConfigManager(
            configFile: directory.appendingPathComponent("config.json"),
            lockFile: directory.appendingPathComponent("config.lock"),
            healthFile: directory.appendingPathComponent("config.health.json")
        )
        recoveryJournalStore = RecoveryJournalStore(
            journalFile: directory.appendingPathComponent("recovery-journal.json"),
            lockFile: directory.appendingPathComponent("recovery-journal.lock")
        )
        try configManager.save(config)
        displays = FakeDisplayManager(displays: initialDisplays)
        virtual = FakeVirtualDisplayManager()
        builtIn = FakeBuiltInDisplayManager()
        sleep = FakeSleepManager()
        touchBar = FakeTouchBarManager()
        rollback = FakeRollbackGuard()
        layout = FakeDisplayLayoutStore()
        operationLock = FakeWorkflowOperationLock()
        virtual.onDestroy = { [weak displays] in
            displays?.currentDisplays.removeAll { $0.isManagedVirtual }
        }
    }

    func seedRecoveryJournal(
        for state: RuntimeState,
        operationID: String = "test-operation",
        stage: RecoveryJournalStage = .headless
    ) throws {
        _ = try recoveryJournalStore.create(operationID: operationID)
        try recoveryJournalStore.update { journal in
            journal.builtInDisplayID = state.softDisconnectedDisplayID ?? state.builtInDisplayID
            journal.builtInWasMain = state.builtInWasMain
            journal.builtInSoftDisconnected = state.builtInSoftDisconnected == true
            journal.softDisconnectMethod = state.builtInSoftDisconnectMethod
            journal.replacementDisplayID = state.replacementDisplayID ?? state.virtualDisplayID
            journal.replacementDisplayType = state.replacementDisplayType
            journal.virtualDisplayHost = state.virtualDisplayHost
            journal.keepAwakeHost = state.keepAwakeHost
            journal.stage = stage
        }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
