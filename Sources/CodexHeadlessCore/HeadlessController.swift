import Foundation

public final class HeadlessController {
    let logger: CHLogger
    let configManager: ConfigManaging
    let stateStore: RuntimeStateStoring
    let recoveryJournalStore: RecoveryJournalStoring
    let sleepManager: SleepManaging
    let displayManager: DisplayManaging
    let displayLayoutStore: DisplayLayoutStoring
    let builtInDisplayManager: BuiltInDisplayManaging
    let virtualDisplayManager: VirtualDisplayManaging
    let touchBarManager: TouchBarManaging
    let rollbackGuard: RollbackDeadlineClearing
    let operationLock: WorkflowOperationLocking
    let clock: WorkflowClock
    let failureInjector: WorkflowFailureInjecting
    let processSnapshotProvider: ManagedProcessSnapshotProviding
    let cancellationLock = NSLock()
    var enableCancellationRequestedInProcess = false

    public init(
        logger: CHLogger = CHLogger(),
        configManager: ConfigManaging = ConfigManager(),
        stateStore: RuntimeStateStoring = StateStore(),
        recoveryJournalStore: RecoveryJournalStoring? = nil,
        sleepManager: SleepManaging? = nil,
        displayManager: DisplayManaging = DisplayManager(),
        displayLayoutStore: DisplayLayoutStoring? = nil,
        builtInDisplayManager: BuiltInDisplayManaging = BuiltInDisplayManager(),
        virtualDisplayManager: VirtualDisplayManaging? = nil,
        touchBarManager: TouchBarManaging = TouchBarManager(),
        rollbackGuard: RollbackDeadlineClearing? = nil,
        operationLock: WorkflowOperationLocking? = nil,
        keepAwakeProcessKind: KeepAwakeProcessKind = .cli,
        clock: WorkflowClock = SystemWorkflowClock(),
        failureInjector: WorkflowFailureInjecting = NoopWorkflowFailureInjector(),
        processSnapshotProvider: ManagedProcessSnapshotProviding = ManagedProcessSnapshotProvider()
    ) {
        self.logger = logger
        self.configManager = configManager
        self.stateStore = stateStore
        self.clock = clock
        self.failureInjector = failureInjector
        self.processSnapshotProvider = processSnapshotProvider
        let resolvedJournalStore = recoveryJournalStore ?? RecoveryJournalStore(logger: logger, clock: clock)
        self.recoveryJournalStore = resolvedJournalStore
        if let sleepManager {
            self.sleepManager = sleepManager
        } else {
            self.sleepManager = SleepManager(
                logger: logger,
                stateStore: stateStore,
                configManager: configManager,
                processKind: keepAwakeProcessKind,
                recoveryJournalStore: resolvedJournalStore,
                clock: clock,
                snapshotProvider: processSnapshotProvider
            )
        }
        self.displayManager = displayManager
        self.displayLayoutStore = displayLayoutStore ?? DisplayLayoutStore(logger: logger)
        self.builtInDisplayManager = builtInDisplayManager
        self.virtualDisplayManager = virtualDisplayManager ?? VirtualDisplayManager(
            logger: logger,
            stateStore: stateStore,
            displayManager: displayManager,
            recoveryJournalStore: resolvedJournalStore,
            clock: clock,
            snapshotProvider: processSnapshotProvider
        )
        self.touchBarManager = touchBarManager
        if let rollbackGuard {
            self.rollbackGuard = rollbackGuard
        } else {
            self.rollbackGuard = RollbackStateStore(stateStore: stateStore, logger: logger)
        }
        self.operationLock = operationLock ?? WorkflowOperationLock(logger: logger, clock: clock)
    }

    public func statusText() -> String {
        var snapshot = StatusSnapshotProvider(
            configManager: configManager,
            stateStore: stateStore,
            displayManager: displayManager,
            builtInDisplayManager: builtInDisplayManager
        ).snapshot()
        let runtimeState = snapshot.state
        if runtimeState.mode == .normal {
            snapshot.cleanNormalAssessment = assessCleanNormal()
        } else {
            snapshot.operationalEvidence = OperationalEvidenceAssessor(
                stateStore: stateStore, journalStore: recoveryJournalStore,
                sleepManager: sleepManager, virtualManager: virtualDisplayManager,
                displayManager: displayManager, snapshotProvider: processSnapshotProvider
            ).assess(state: runtimeState, source: .explicitStatus)
        }
        do {
            snapshot.journal = try recoveryJournalStore.read()
        } catch {
            snapshot.journalError = error.localizedDescription
        }
        return StatusReportBuilder(snapshot: snapshot).build()
    }
}
