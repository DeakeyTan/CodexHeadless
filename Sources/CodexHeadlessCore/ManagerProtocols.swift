import Foundation

public protocol ConfigManaging: AnyObject {
    func load() -> AppConfig
    func read() throws -> AppConfig
    func health() -> ConfigHealth
    func blockSoftDisconnect(reason: String) throws
}

extension ConfigManager: ConfigManaging {}

public protocol DisplayManaging: AnyObject {
    func displays() -> [DisplayInfo]
    func hasAlternativeDisplay() -> Bool
    func preferredExternalDisplay() -> DisplayInfo?
    func display(id: UInt32) -> DisplayInfo?
    func waitForDisplay(id: UInt32, present expectedPresent: Bool, timeoutSeconds: TimeInterval) -> Bool
    func setMainDisplayToRestorePriority(managedVirtualDisplayID: UInt32?) throws
    func restorePriorityDisplay(managedVirtualDisplayID: UInt32?) -> DisplayInfo?
    func waitForRestorePriorityDisplay(managedVirtualDisplayID: UInt32?, timeoutSeconds: TimeInterval) -> DisplayInfo?
    func setMainDisplay(id targetID: UInt32, reason: String, fallbackResolution: Resolution?) throws -> Bool
    func restoreLayout(from snapshot: DisplayLayoutSnapshot, managedVirtualDisplayID: UInt32?) throws -> DisplayLayoutRestoreResult
    func compactStatus(displays: [DisplayInfo]?) -> String
    func statusLines(managedVirtualDisplayID: UInt32?) -> [String]
    func verifyPhysicalTakeover(displayID: UInt32, managedVirtualDisplayID: UInt32?, stabilizationSeconds: TimeInterval) -> DisplayTakeoverVerification
}

public extension DisplayManaging {
    func setMainDisplay(id targetID: UInt32, reason: String) throws -> Bool {
        try setMainDisplay(id: targetID, reason: reason, fallbackResolution: nil)
    }

    func compactStatus() -> String { compactStatus(displays: nil) }
}

extension DisplayManager: DisplayManaging {}

public protocol VirtualDisplayManaging: AnyObject {
    func validateResolution(_ resolution: Resolution) throws
    func createVirtualDisplay(
        resolution: Resolution,
        refreshRate: Int,
        scaleMode: String,
        waitTimeoutSeconds: TimeInterval,
        reportedIDExtraWaitSeconds: TimeInterval
    ) throws -> UInt32?
    func destroyVirtualDisplayIfManaged() -> ManagedResourceCleanupResult
    func reconcileManagedVirtualDisplayIfNeeded()
    func reconcileManagedVirtualDisplayIfNeeded(displays: [DisplayInfo])
    func recoveryHostRecord() -> VirtualDisplayHostRecord?
    func managedResourceObservation(snapshot: ManagedProcessSnapshot?) -> ManagedResourceObservation
}

public extension VirtualDisplayManaging {
    func reconcileManagedVirtualDisplayIfNeeded(displays: [DisplayInfo]) { reconcileManagedVirtualDisplayIfNeeded() }
    func managedResourceObservation(snapshot: ManagedProcessSnapshot? = nil) -> ManagedResourceObservation {
        recoveryHostRecord().map { .init(status: .verifiedOwned, summary: "verified virtual display host", pid: $0.pid) } ?? .none
    }
}

extension VirtualDisplayManager: VirtualDisplayManaging {}

public protocol BuiltInDisplayManaging: AnyObject {
    func currentBrightness() -> Float?
    func brightnessCapability() -> BrightnessCapability
    func dimBuiltInDisplay() -> BrightnessChangeResult
    func restoreBrightness(_ brightness: Float?) -> BrightnessChangeResult
    func attemptSoftDisconnectIfSafe(builtInDisplayID: UInt32?, hasAlternativeDisplay: Bool, enabled: Bool) -> SoftDisconnectResult
    func restoreBuiltInDisplay(displayID: UInt32?) -> SoftDisconnectResult
}

extension BuiltInDisplayManager: BuiltInDisplayManaging {}

public protocol SleepManaging: AnyObject {
    func enableKeepAwake() throws
    func disableKeepAwake() -> ManagedResourceCleanupResult
    func syncWithState()
    func applyDisplaySleepFast()
    func recoveryHostRecord() -> KeepAwakeHostRecord?
    func managedResourceObservation(snapshot: ManagedProcessSnapshot?) -> ManagedResourceObservation
}

public extension SleepManaging {
    func managedResourceObservation(snapshot: ManagedProcessSnapshot? = nil) -> ManagedResourceObservation {
        recoveryHostRecord().map { .init(status: .verifiedOwned, summary: "verified Keep Awake holder", pid: $0.pid) } ?? .none
    }
}

extension SleepManager: SleepManaging {}

public protocol TouchBarManaging: AnyObject {
    func hideIfEnabled(_ enabled: Bool) -> TouchBarChangeResult
    func showIfNeeded(_ wasHidden: Bool?) -> TouchBarChangeResult
}

extension TouchBarManager: TouchBarManaging {}

public protocol RollbackDeadlineClearing: AnyObject {
    func cancel() throws
}

extension RollbackStateStore: RollbackDeadlineClearing {}

public protocol DisplayLayoutStoring: AnyObject {
    func loadMatching(displays: [DisplayInfo]) throws -> DisplayLayoutSnapshot
    func saveCurrentLayout(displayManager: DisplayManaging, reason: String, includeManagedVirtual: Bool)
}

public extension DisplayLayoutStoring {
    func saveCurrentLayout(displayManager: DisplayManaging, reason: String) {
        saveCurrentLayout(displayManager: displayManager, reason: reason, includeManagedVirtual: false)
    }
}

extension DisplayLayoutStore: DisplayLayoutStoring {}

public protocol WorkflowOperationLeaseHandling: AnyObject {
    var operationID: String { get }
    func release()
}

public protocol WorkflowOperationLocking: AnyObject {
    func acquire(name: String, timeoutSeconds: TimeInterval, logLifecycle: Bool) throws -> WorkflowOperationLeaseHandling
}

public extension WorkflowOperationLocking {
    func acquire(name: String) throws -> WorkflowOperationLeaseHandling {
        try acquire(name: name, timeoutSeconds: 60, logLifecycle: true)
    }

    func acquire(name: String, timeoutSeconds: TimeInterval) throws -> WorkflowOperationLeaseHandling {
        try acquire(name: name, timeoutSeconds: timeoutSeconds, logLifecycle: true)
    }
}
