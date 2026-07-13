import Foundation

public protocol CleanNormalAssessing {
    func assess(
        allowingFinalizingJournalOperationID: String?,
        snapshot: ManagedProcessSnapshot?
    ) -> CleanNormalAssessment
}

public extension CleanNormalAssessing {
    func assess() -> CleanNormalAssessment {
        assess(allowingFinalizingJournalOperationID: nil, snapshot: nil)
    }
}

public struct CleanNormalAssessor: CleanNormalAssessing {
    private let stateStore: RuntimeStateStoring
    private let recoveryJournalStore: RecoveryJournalStoring
    private let sleepManager: SleepManaging
    private let virtualDisplayManager: VirtualDisplayManaging
    private let displayManager: DisplayManaging
    private let snapshotProvider: ManagedProcessSnapshotProviding

    public init(
        stateStore: RuntimeStateStoring,
        recoveryJournalStore: RecoveryJournalStoring,
        sleepManager: SleepManaging,
        virtualDisplayManager: VirtualDisplayManaging,
        displayManager: DisplayManaging,
        snapshotProvider: ManagedProcessSnapshotProviding = ManagedProcessSnapshotProvider()
    ) {
        self.stateStore = stateStore
        self.recoveryJournalStore = recoveryJournalStore
        self.sleepManager = sleepManager
        self.virtualDisplayManager = virtualDisplayManager
        self.displayManager = displayManager
        self.snapshotProvider = snapshotProvider
    }

    public func assess(
        allowingFinalizingJournalOperationID: String? = nil,
        snapshot suppliedSnapshot: ManagedProcessSnapshot? = nil
    ) -> CleanNormalAssessment {
        var runtime: [String] = []
        var journalViolation: String?
        var observed: [String] = []
        var display: [String] = []
        var runtimeReadSucceeded = true
        var journalReadSucceeded = true
        let state: RuntimeState
        do {
            state = try stateStore.read()
            if state.mode != .normal { runtime.append("Runtime mode is \(state.mode.rawValue), not Normal.") }
            if state.keepAwake { runtime.append("Runtime records Keep Awake On.") }
            if state.keepAwakeHost != nil || state.caffeinatePID != nil || state.keepAwakeBackend != nil {
                runtime.append("Runtime retains a Keep Awake owner record.")
            }
            if state.virtualDisplayCreated || state.virtualDisplayHost != nil || state.virtualDisplayPID != nil || state.virtualDisplayID != nil {
                runtime.append("Runtime retains a managed virtual display record.")
            }
            if state.builtInSoftDisconnected == true { runtime.append("Runtime records the built-in display as soft-disconnected.") }
            if state.builtInBrightnessDimmed == true { runtime.append("Runtime records the built-in display brightness as dimmed.") }
            if state.touchBarHidden == true { runtime.append("Runtime records the Touch Bar as hidden.") }
        } catch {
            state = .recoveryRequired(message: error.localizedDescription)
            runtimeReadSucceeded = false
            runtime.append("RuntimeState cannot be read: \(error.localizedDescription)")
        }

        do {
            if let journal = try recoveryJournalStore.read(),
               journal.operationID != allowingFinalizingJournalOperationID {
                journalViolation = "Recovery Journal is active at stage \(journal.stage.rawValue)."
            }
        } catch {
            journalReadSucceeded = false
            journalViolation = "Recovery Journal cannot be safely interpreted: \(error.localizedDescription)"
        }

        let snapshot = suppliedSnapshot ?? snapshotProvider.capture()
        let keepAwake = sleepManager.managedResourceObservation(snapshot: snapshot)
        if keepAwake.status != .none { observed.append("Keep Awake observation is \(keepAwake.status.rawValue): \(keepAwake.summary)") }
        let virtual = virtualDisplayManager.managedResourceObservation(snapshot: snapshot)
        if virtual.status != .none { observed.append("Virtual display observation is \(virtual.status.rawValue): \(virtual.summary)") }

        let displays = displayManager.displays()
        let managedDisplayPresent = displays.contains(where: { $0.isManagedVirtual })
        if managedDisplayPresent {
            display.append("A managed virtual display is still enumerated.")
        }
        let usablePhysical = displays.contains { !$0.isManagedVirtual && $0.isActive && $0.isOnline && $0.isMain }
        let physicalMainPresent = displays.contains { !$0.isManagedVirtual && $0.isOnline && $0.isMain }
        let physicalTemporarilyUnavailable = !usablePhysical && (physicalMainPresent || !managedDisplayPresent)
        if physicalTemporarilyUnavailable {
            display.append("The main physical display is temporarily inactive or unavailable.")
        }

        return CleanNormalAssessment(
            runtimeViolations: runtime,
            journalViolation: journalViolation,
            observedResourceViolations: observed,
            displayViolations: display,
            keepAwakeObservation: keepAwake,
            virtualDisplayObservation: virtual,
            runtimeReadSucceeded: runtimeReadSucceeded,
            journalReadSucceeded: journalReadSucceeded,
            processSnapshotSucceeded: snapshot.succeeded,
            processSnapshotError: snapshot.error,
            managedDisplayViolation: managedDisplayPresent,
            physicalDisplayTemporarilyUnavailable: physicalTemporarilyUnavailable
        )
    }

    public func requireCleanNormal(for operation: String) throws {
        let result = assess()
        guard result.isClean else {
            let detail = result.violations.joined(separator: " ")
            if result.classification == .temporarilyUnavailable {
                throw CodexHeadlessError.managedResource(
                    message: "Cannot \(operation) because the physical display is temporarily unavailable. Wake the screen and try again. \(detail)"
                )
            }
            throw CodexHeadlessError.managedResource(message: "Cannot \(operation): \(result.recommendedAction) \(detail)")
        }
    }
}

public extension HeadlessController {
    func assessCleanNormal() -> CleanNormalAssessment {
        CleanNormalAssessor(
            stateStore: stateStore,
            recoveryJournalStore: recoveryJournalStore,
            sleepManager: sleepManager,
            virtualDisplayManager: virtualDisplayManager,
            displayManager: displayManager,
            snapshotProvider: processSnapshotProvider
        ).assess()
    }
}
