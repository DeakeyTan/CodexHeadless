import Foundation

final class ConfigurationMutationGuard {
    private let stateStore: RuntimeStateStoring
    private let recoveryJournalStore: RecoveryJournalStoring
    private let displayManager: DisplayManaging
    private let operationLock: WorkflowOperationLocking
    private let snapshotProvider: ManagedProcessSnapshotProviding

    init(
        stateStore: RuntimeStateStoring = StateStore(),
        recoveryJournalStore: RecoveryJournalStoring = RecoveryJournalStore(),
        displayManager: DisplayManaging = DisplayManager(),
        operationLock: WorkflowOperationLocking = WorkflowOperationLock(),
        snapshotProvider: ManagedProcessSnapshotProviding = ManagedProcessSnapshotProvider()
    ) {
        self.stateStore = stateStore
        self.recoveryJournalStore = recoveryJournalStore
        self.displayManager = displayManager
        self.operationLock = operationLock
        self.snapshotProvider = snapshotProvider
    }

    func acquire() throws -> WorkflowOperationLeaseHandling {
        let lease = try operationLock.acquire(name: "config-mutation")
        do {
            let state = try stateStore.read()
            guard state.mode == .normal,
                  !state.keepAwake,
                  state.keepAwakeHost == nil,
                  state.caffeinatePID == nil,
                  !state.virtualDisplayCreated,
                  state.virtualDisplayHost == nil,
                  state.virtualDisplayPID == nil,
                  state.virtualDisplayID == nil,
                  state.builtInSoftDisconnected != true,
                  state.builtInBrightnessDimmed != true,
                  state.touchBarHidden != true else {
                throw CodexHeadlessError.invalidMode(current: state.mode, requestedOperation: "modify configuration")
            }
            guard try recoveryJournalStore.read() == nil else {
                throw CodexHeadlessError.recoveryJournalUnavailable(message: "Recovery Journal is active; Restore before changing configuration.")
            }
            let displays = displayManager.displays()
            guard !displays.contains(where: { $0.isManagedVirtual }),
                  displays.contains(where: { !$0.isManagedVirtual && $0.isActive && $0.isOnline && $0.isMain }) else {
                throw CodexHeadlessError.managedResource(message: "Display topology is not Clean Normal.")
            }
            let snapshot = snapshotProvider.capture()
            guard snapshot.succeeded else {
                throw CodexHeadlessError.managedResource(
                    message: "Managed process ownership is unknown: \(snapshot.error ?? "process snapshot unavailable")."
                )
            }
            if snapshot.entries.contains(where: {
                HelperProcessCandidateDetector.hasExactCommandStructure($0.command, kind: .keepAwakeHost)
                    || HelperProcessCandidateDetector.hasExactCommandStructure($0.command, kind: .virtualDisplayHost)
            }) {
                throw CodexHeadlessError.managedResource(message: "A possible managed helper process is still running.")
            }
            return lease
        } catch {
            lease.release()
            throw error
        }
    }
}
