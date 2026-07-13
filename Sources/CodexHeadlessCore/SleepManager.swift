import Darwin
import Foundation
import IOKit.pwr_mgt

public enum KeepAwakeProcessKind: String {
    case app
    case cli
}

public final class SleepManager {
    private let logger: CHLogger
    private let stateStore: RuntimeStateStoring
    private let configManager: ConfigManaging
    private let processKind: KeepAwakeProcessKind
    private let processInspector: ManagedProcessInspecting
    private let recoveryJournalStore: RecoveryJournalStoring
    private let capabilityStore: HelperCapabilityStore
    private let failureInjector: ManagedResourceFailureInjecting
    private let clock: WorkflowClock
    private let snapshotProvider: ManagedProcessSnapshotProviding

    public init(
        logger: CHLogger = CHLogger(),
        stateStore: RuntimeStateStoring = StateStore(),
        configManager: ConfigManaging = ConfigManager(),
        processKind: KeepAwakeProcessKind = .cli,
        processInspector: ManagedProcessInspecting = ManagedProcessInspector(),
        recoveryJournalStore: RecoveryJournalStoring = RecoveryJournalStore(),
        capabilityStore: HelperCapabilityStore? = nil,
        failureInjector: ManagedResourceFailureInjecting = NoopManagedResourceFailureInjector(),
        clock: WorkflowClock = SystemWorkflowClock(),
        snapshotProvider: ManagedProcessSnapshotProviding = ManagedProcessSnapshotProvider()
    ) {
        self.logger = logger
        self.stateStore = stateStore
        self.configManager = configManager
        self.processKind = processKind
        self.processInspector = processInspector
        self.recoveryJournalStore = recoveryJournalStore
        self.capabilityStore = capabilityStore ?? HelperCapabilityStore(journalStore: recoveryJournalStore)
        self.failureInjector = failureInjector
        self.clock = clock
        self.snapshotProvider = snapshotProvider
    }

    public func enableKeepAwake() throws {
        let started = clock.uptime
        defer { logger.info("[Perf] keep-awake-start durationMs=\(Int((clock.uptime - started) * 1000))") }
        let requested = try configManager.read().keepAwakeBackend ?? .caffeinate
        let backend: KeepAwakeBackend = .caffeinate
        if requested == .native {
            logger.warn("Native Keep Awake is not used by Headless Mode; migrated to managed caffeinate for cross-process recovery.")
        }
        let current = try stateStore.read()
        if current.keepAwake,
           current.keepAwakeBackend != nil,
           current.keepAwakeBackend != backend.rawValue {
            let cleanup = disableKeepAwake()
            guard cleanup.completed else {
                throw CodexHeadlessError.managedResource(
                    message: "Cannot switch Keep Awake backend because existing cleanup \(cleanup.summary)."
                )
            }
        }
        switch backend {
        case .caffeinate: try enableCaffeinate()
        case .native: break
        }
    }

    public func disableKeepAwake() -> ManagedResourceCleanupResult {
        let started = clock.uptime
        defer { logger.info("[Perf] keep-awake-stop durationMs=\(Int((clock.uptime - started) * 1000))") }
        let state: RuntimeState
        do {
            state = try stateStore.read()
        } catch {
            return .failed(reason: "Runtime state is unavailable: \(error.localizedDescription)")
        }

        let journal: RecoveryJournal?
        do {
            journal = try recoveryJournalStore.read()
        } catch {
            return .failed(reason: "Recovery Journal is unavailable: \(error.localizedDescription)")
        }
        let cleanup: ManagedResourceCleanupResult
        do {
            try failureInjector.check(.beforeCleanup, resourceKind: "keep-awake")
        } catch {
            return .failed(reason: error.localizedDescription)
        }
        if state.keepAwakeBackend == KeepAwakeBackend.native.rawValue {
            return .ownershipMismatch(reason: "Legacy Native assertion cannot be released or verified by this v0.9.x workflow. Quit its owner process, then retry Restore.")
        } else if let record = journal?.keepAwakeHost ?? state.keepAwakeHost, let pid = record.pid {
            guard trustedRecordMatchesState(record, state: state) else {
                return .ownershipMismatch(reason: "Recovery journal does not independently verify Keep Awake instance \(record.instanceID).")
            }
            cleanup = processInspector.terminate(identity(for: record, pid: pid), timeoutSeconds: 1.5)
        } else if state.caffeinatePID != nil
                    || (journal?.keepAwakeResource != nil && journal?.keepAwakeResource?.stage != .cleaned) {
            cleanup = .ownershipMismatch(reason: "Legacy caffeinate PID has no instance ownership record.")
        } else {
            cleanup = .alreadyStopped
        }

        guard cleanup.completed else {
            logger.error("Keep Awake cleanup \(cleanup.summary); state remains On for recovery.")
            return cleanup
        }
        do {
            try failureInjector.check(.afterTerminateRequest, resourceKind: "keep-awake")
        } catch {
            return .failed(reason: error.localizedDescription)
        }
        if let pid = (journal?.keepAwakeHost ?? state.keepAwakeHost)?.pid,
           processInspector.isRunning(pid: pid) {
            return .failed(reason: "Keep Awake assertion holder PID \(pid) is still running after cleanup.")
        }
        do {
            try failureInjector.check(.afterResourceDisappearCheck, resourceKind: "keep-awake")
        } catch {
            return .failed(reason: error.localizedDescription)
        }
        do {
            try stateStore.transaction { runtime in
                runtime.keepAwake = false
                runtime.caffeinatePID = nil
                runtime.keepAwakeBackend = nil
                runtime.keepAwakeHost = nil
            }
            if journal != nil {
                try recoveryJournalStore.update { journal in
                    journal.keepAwakeHost = nil
                    journal.keepAwakeResource?.stage = .cleaned
                    journal.cleanupProgress.keepAwakeCleanup = .completed
                    journal.cleanupProgress.keepAwakeHolderStop = .completed
                    journal.cleanupProgress.keepAwakeAssertionDisappearance = .completed
                }
            }
            try StandaloneJournalFinalizer(
                stateStore: stateStore,
                journalStore: recoveryJournalStore,
                snapshotProvider: snapshotProvider
            ).finalizeIfClean()
            logger.info("Keep Awake cleanup \(cleanup.summary).")
            return cleanup
        } catch {
            logger.error("Keep Awake stopped but state persistence failed: \(error.localizedDescription)")
            return .failed(reason: "Resource stopped but state persistence failed: \(error.localizedDescription)")
        }
    }

    public func syncWithState() {
        let state: RuntimeState
        do {
            state = try stateStore.read()
        } catch {
            logger.error("Keep Awake reconcile skipped because runtime state is unavailable: \(error.localizedDescription)")
            return
        }
        guard state.keepAwake else {
            return
        }

        if state.keepAwakeBackend == KeepAwakeBackend.native.rawValue {
            logger.warn("Legacy Native Keep Awake state requires explicit Restore before migration.")
            return
        }

        if let record = state.keepAwakeHost, let pid = record.pid {
            if processInspector.matches(identity(for: record, pid: pid)) { return }
            if processInspector.isRunning(pid: pid) {
                logger.error("Keep Awake ownership mismatch for live PID \(pid); refusing automatic replacement.")
                return
            }
        }
        logger.warn("Managed Keep Awake process is missing; restarting it.")
        do { try enableCaffeinate(forceRestart: true) } catch { logger.error("Keep Awake self-heal failed: \(error.localizedDescription)") }
    }

    public func applyDisplaySleepFast() {
        // Keep Awake is process-scoped. CodexHeadless no longer mutates global pmset values.
    }

    public func recoveryHostRecord() -> KeepAwakeHostRecord? {
        guard let journal = try? recoveryJournalStore.read(),
              let record = journal.keepAwakeHost,
              let pid = record.pid,
              processInspector.matches(identity(for: record, pid: pid)) else { return nil }
        return record
    }

    public func managedResourceObservation(snapshot suppliedSnapshot: ManagedProcessSnapshot? = nil) -> ManagedResourceObservation {
        do {
            if let journal = try recoveryJournalStore.read(), let record = journal.keepAwakeHost, let pid = record.pid {
                if processInspector.matches(identity(for: record, pid: pid)) {
                    return .init(status: .verifiedOwned, summary: "IOPM assertion holder identity matches Recovery Journal", pid: pid)
                }
                if processInspector.isRunning(pid: pid) {
                    return .init(status: .unknown, summary: "recorded Keep Awake PID is running with mismatched ownership", pid: pid)
                }
            }
        } catch {
            return .init(status: .unknown, summary: "Recovery Journal cannot be read: \(error.localizedDescription)")
        }
        let snapshot = suppliedSnapshot ?? snapshotProvider.capture()
        guard snapshot.succeeded else {
            return .init(status: .unknown, summary: snapshot.error ?? "process snapshot unavailable")
        }
        switch HelperProcessCandidateDetector.verify(
            snapshot: snapshot, kind: .keepAwakeHost, inspector: processInspector
        ) {
        case .verified(let pid):
            return .init(status: .possibleOwned, summary: "an authorized-helper-shaped Keep Awake process is present without verified ownership", pid: pid)
        case .unknown(let pid, let reason):
            return .init(status: .unknown, summary: reason, pid: pid)
        case .none:
            return .none
        }
    }

    private func enableCaffeinate(forceRestart: Bool = false) throws {
        let current = try stateStore.read()
        if !forceRestart,
           let record = current.keepAwakeHost,
           let pid = record.pid,
           record.backend == .caffeinate,
           processInspector.matches(identity(for: record, pid: pid)) {
            logger.info("Managed Keep Awake is already active: PID \(pid), instance=\(record.instanceID).")
            return
        }
        if let record = current.keepAwakeHost,
           let pid = record.pid,
           processInspector.isRunning(pid: pid),
           !processInspector.matches(identity(for: record, pid: pid)) {
            throw CodexHeadlessError.managedResource(
                message: "Refusing to replace live Keep Awake PID \(pid) because ownership does not match."
            )
        }

        let instanceID = UUID().uuidString.lowercased()
        try failureInjector.check(.beforeIntentJournal, resourceKind: "keep-awake")
        let helperPath = HelperExecutableResolver.resolveCodexHeadless()
            ?? CommandLine.arguments.first
            ?? "codex-headless"
        let operationID: String
        if let journal = try recoveryJournalStore.read() {
            operationID = journal.operationID
        } else {
            operationID = "standalone-keep-awake-\(instanceID)"
            _ = try recoveryJournalStore.create(operationID: operationID)
        }
        try recoveryJournalStore.update { journal in
            journal.keepAwakeResource = ManagedResourceJournalRecord(
                instanceID: instanceID,
                resourceKind: "keep-awake",
                operationID: operationID,
                stage: .intent
            )
        }
        try failureInjector.check(.afterIntentJournal, resourceKind: "keep-awake")
        let capability = try capabilityStore.reserve(
            kind: .keepAwakeHost,
            operationID: operationID,
            expectedExecutablePath: helperPath
        )
        let process = Process()
        let output = Pipe()
        let outputCollector = KeepAwakeOutputCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            outputCollector.append(handle.availableData)
        }
        process.standardOutput = output
        process.standardError = output
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = [
            "internal-helper",
            InternalHelperKind.keepAwakeHost.rawValue,
            capability.capabilityID,
            capability.nonce,
            capability.operationID,
            instanceID
        ]
        try process.run()
        do {
            try failureInjector.check(.afterProcessStart, resourceKind: "keep-awake")
        } catch {
            process.terminate()
            let deadline = clock.uptime + 1
            while process.isRunning && clock.uptime < deadline { clock.sleep(seconds: 0.02) }
            try? recoveryJournalStore.update {
                $0.keepAwakeResource?.stage = process.isRunning ? .cleanupPending : .cleaned
            }
            guard !process.isRunning else {
                throw CodexHeadlessError.managedResource(message: "Keep Awake start failed and holder cleanup is unconfirmed. Recovery Journal was preserved.")
            }
            throw error
        }
        try recoveryJournalStore.update { $0.keepAwakeResource?.stage = .started }
        let ownershipDeadline = clock.uptime + 1.5
        var processFacts = processInspector.facts(pid: process.processIdentifier)
        while (processFacts?.processStartTime == nil
                || processFacts?.executableFileIdentity == nil
                || !outputCollector.contains("assertion-created")),
              clock.uptime < ownershipDeadline {
            clock.sleep(seconds: 0.02)
            processFacts = processInspector.facts(pid: process.processIdentifier)
        }
        guard let processFacts,
              processFacts.processStartTime != nil,
              processFacts.executableFileIdentity != nil,
              process.isRunning,
              outputCollector.contains("assertion-created") else {
            process.terminate()
            let cleanupDeadline = clock.uptime + 1
            while process.isRunning && clock.uptime < cleanupDeadline { clock.sleep(seconds: 0.02) }
            try recoveryJournalStore.update { journal in
                journal.keepAwakeResource?.stage = process.isRunning ? .cleanupPending : .cleaned
            }
            throw CodexHeadlessError.keepAwakeOwnership(
                message: "Could not verify that the Keep Awake helper created its IOPM assertion."
            )
        }
        var runtimeCommitted = false
        let createdAt = clock.now
        let record = KeepAwakeHostRecord(
            instanceID: instanceID,
            pid: process.processIdentifier,
            backend: .caffeinate,
            executablePath: helperPath,
            startedAt: createdAt,
            ownerProcessKind: processKind.rawValue,
            ownership: ManagedProcessOwnershipRecord(
                instanceID: instanceID,
                pid: process.processIdentifier,
                executableCanonicalPath: processFacts.executableCanonicalPath,
                executableFileIdentity: processFacts.executableFileIdentity,
                processStartTime: processFacts.processStartTime,
                expectedCommandFragments: ["internal-helper", InternalHelperKind.keepAwakeHost.rawValue, capability.capabilityID, instanceID],
                ownerOperationID: operationID,
                resourceKind: "keep-awake",
                createdAt: createdAt
            ),
            assertionKind: "PreventUserIdleSystemSleep"
        )
        do {
            try failureInjector.check(.afterOwnershipObservation, resourceKind: "keep-awake")
            try recoveryJournalStore.update { journal in
                journal.keepAwakeHost = record
                journal.keepAwakeResource?.ownership = record.ownership
                journal.keepAwakeResource?.stage = .observed
                journal.stage = .keepAwakeStarted
            }
            try failureInjector.check(.afterObservedJournal, resourceKind: "keep-awake")
            try failureInjector.check(.beforeRuntimeCommit, resourceKind: "keep-awake")
            try stateStore.transaction { state in
                state.keepAwake = true
                state.caffeinatePID = process.processIdentifier
                state.keepAwakeBackend = KeepAwakeBackend.caffeinate.rawValue
                state.keepAwakeHost = record
            }
            runtimeCommitted = true
            try failureInjector.check(.afterRuntimeCommit, resourceKind: "keep-awake")
            try recoveryJournalStore.update { $0.keepAwakeResource?.stage = .committed }
        } catch {
            let cleanup = processInspector.terminate(identity(for: record, pid: process.processIdentifier), timeoutSeconds: 1)
            try compensateFailedStart(record: record, runtimeCommitted: runtimeCommitted, cleanup: cleanup)
            throw error
        }
        logger.info("Started managed Keep Awake PID \(process.processIdentifier), instance=\(instanceID).")
    }

    private func identity(for record: KeepAwakeHostRecord, pid: Int32) -> ManagedProcessIdentity {
        ManagedProcessIdentity(
            pid: pid,
            executablePath: record.executablePath ?? "codex-headless",
            requiredCommandFragments: record.ownership?.expectedCommandFragments
                ?? ["internal-helper", InternalHelperKind.keepAwakeHost.rawValue, record.instanceID],
            expectedStartTime: record.ownership?.processStartTime,
            expectedExecutableFileIdentity: record.ownership?.executableFileIdentity
        )
    }

    func compensateFailedStart(
        record: KeepAwakeHostRecord,
        runtimeCommitted: Bool,
        cleanup: ManagedResourceCleanupResult
    ) throws {
        guard cleanup.completed else {
            try? recoveryJournalStore.update { $0.keepAwakeResource?.stage = .cleanupPending }
            throw CodexHeadlessError.managedResource(
                message: "Keep Awake commit failed and holder cleanup is unconfirmed: \(cleanup.summary). Recovery Journal was preserved."
            )
        }
        if runtimeCommitted {
            do {
                try stateStore.transaction { runtime in
                    runtime.keepAwake = false
                    runtime.caffeinatePID = nil
                    runtime.keepAwakeBackend = nil
                    runtime.keepAwakeHost = nil
                }
            } catch let compensationError {
                try? recoveryJournalStore.update { $0.keepAwakeResource?.stage = .cleanupPending }
                throw CodexHeadlessError.managedResource(
                    message: "Keep Awake stopped, but RuntimeState compensation failed: \(compensationError.localizedDescription). Recovery Journal ownership was preserved."
                )
            }
        }
        try recoveryJournalStore.update { journal in
            journal.keepAwakeResource?.stage = .cleaned
            journal.keepAwakeHost = nil
        }
    }

    private func trustedRecordMatchesState(_ record: KeepAwakeHostRecord, state: RuntimeState) -> Bool {
        guard record.ownership != nil else { return false }
        guard let journal = try? recoveryJournalStore.read(),
              let trusted = journal.keepAwakeHost,
              let stateRecord = state.keepAwakeHost else { return false }
        return trusted.instanceID == record.instanceID
            && trusted.pid == record.pid
            && trusted.ownership == record.ownership
            && stateRecord.instanceID == record.instanceID
            && stateRecord.pid == record.pid
            && stateRecord.ownership == record.ownership
            && journal.keepAwakeResource?.operationID == record.ownership?.ownerOperationID
    }

}

private final class KeepAwakeOutputCollector {
    private let lock = NSLock()
    private var text = ""
    func append(_ data: Data) {
        guard let value = String(data: data, encoding: .utf8) else { return }
        lock.lock(); text += value; lock.unlock()
    }
    func contains(_ value: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return text.contains(value)
    }
}
