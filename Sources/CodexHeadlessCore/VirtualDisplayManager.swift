import Foundation
import CoreGraphics
import Darwin
import ObjectiveC.runtime

public struct VirtualDisplayProbeReport {
    public var coreGraphicsLoaded: Bool
    public var cgVirtualDisplayClassAvailable: Bool
    public var descriptorClassAvailable: Bool
    public var modeClassAvailable: Bool
    public var settingsClassAvailable: Bool
    public var sdkHeaderAvailable: Bool

    public var text: String {
        """
        CodexHeadless Virtual Display Probe
        -----------------------------------
        CoreGraphics Loaded: \(coreGraphicsLoaded ? "Yes" : "No")
        CGVirtualDisplay Runtime Class: \(cgVirtualDisplayClassAvailable ? "Available" : "Missing")
        CGVirtualDisplayDescriptor Runtime Class: \(descriptorClassAvailable ? "Available" : "Missing")
        CGVirtualDisplayMode Runtime Class: \(modeClassAvailable ? "Available" : "Missing")
        CGVirtualDisplaySettings Runtime Class: \(settingsClassAvailable ? "Available" : "Missing")
        SDK Header Support: \(sdkHeaderAvailable ? "Available" : "Missing in current Command Line Tools SDK")

        Result: \(cgVirtualDisplayClassAvailable && descriptorClassAvailable ? "Software virtual display host can be explored." : "Software virtual display API is not available in this runtime/SDK path.")
        """
    }
}

enum VirtualDisplayAuthorizationWaitResult: Equatable {
    case authorized
    case helperExited(exitCode: Int32, reason: String)
    case timedOut
    case invalidHandshake(String)
}

enum VirtualDisplayLaunchWaitResult: Equatable {
    case ready(displayID: UInt32)
    case helperExited(exitCode: Int32, reason: String)
    case displayTimedOut(reportedDisplayID: UInt32?)
    case invalidHandshake(String)
}

public final class VirtualDisplayManager {
    private let logger: CHLogger
    private let stateStore: RuntimeStateStoring
    private let displayManager: DisplayManaging
    private let processInspector: ManagedProcessInspecting
    private let recoveryJournalStore: RecoveryJournalStoring
    private let capabilityStore: HelperCapabilityStore
    private let failureInjector: ManagedResourceFailureInjecting
    private let clock: WorkflowClock
    private let snapshotProvider: ManagedProcessSnapshotProviding
    private lazy var launchJournalCoordinator = VirtualDisplayLaunchJournalCoordinator(
        journalStore: recoveryJournalStore
    )

    public init(
        logger: CHLogger = CHLogger(),
        stateStore: RuntimeStateStoring = StateStore(),
        displayManager: DisplayManaging = DisplayManager(),
        processInspector: ManagedProcessInspecting = ManagedProcessInspector(),
        recoveryJournalStore: RecoveryJournalStoring = RecoveryJournalStore(),
        capabilityStore: HelperCapabilityStore? = nil,
        failureInjector: ManagedResourceFailureInjecting = NoopManagedResourceFailureInjector(),
        clock: WorkflowClock = SystemWorkflowClock(),
        snapshotProvider: ManagedProcessSnapshotProviding = ManagedProcessSnapshotProvider()
    ) {
        self.logger = logger
        self.stateStore = stateStore
        self.displayManager = displayManager
        self.processInspector = processInspector
        self.recoveryJournalStore = recoveryJournalStore
        self.capabilityStore = capabilityStore ?? HelperCapabilityStore(journalStore: recoveryJournalStore)
        self.failureInjector = failureInjector
        self.clock = clock
        self.snapshotProvider = snapshotProvider
    }

    public func validateResolution(_ resolution: Resolution) throws {
        try ResolutionManager.validate(resolution)
    }

    public func probe() -> VirtualDisplayProbeReport {
        VirtualDisplayProbeReport(
            coreGraphicsLoaded: true,
            cgVirtualDisplayClassAvailable: NSClassFromString("CGVirtualDisplay") != nil,
            descriptorClassAvailable: NSClassFromString("CGVirtualDisplayDescriptor") != nil,
            modeClassAvailable: NSClassFromString("CGVirtualDisplayMode") != nil,
            settingsClassAvailable: NSClassFromString("CGVirtualDisplaySettings") != nil,
            sdkHeaderAvailable: false
        )
    }

    public func createVirtualDisplay(
        resolution: Resolution,
        refreshRate: Int = 60,
        scaleMode: String = "standard",
        waitTimeoutSeconds: TimeInterval = 5,
        reportedIDExtraWaitSeconds: TimeInterval = 2
    ) throws -> UInt32? {
        let started = clock.uptime
        defer { logger.info("[Perf] virtual-display-start durationMs=\(Int((clock.uptime - started) * 1000))") }
        try validateResolution(resolution)
        reconcileManagedVirtualDisplayIfNeeded()
        if let existingID = activeManagedVirtualDisplayID() {
            logger.info("Managed software virtual display already running: \(existingID).")
            return existingID
        }

        guard let helperPath = HelperExecutableResolver.resolveCodexHeadless() else {
            logger.warn("No codex-headless helper executable was available for virtual display host.")
            return nil
        }

        let beforeIDs = Set(displayManager.displays().map(\.id))
        let instanceID = UUID().uuidString.lowercased()
        try failureInjector.check(.beforeIntentJournal, resourceKind: "virtual-display")
        let operationID: String
        if let journal = try recoveryJournalStore.read() {
            operationID = journal.operationID
        } else {
            operationID = "standalone-virtual-display-\(instanceID)"
            _ = try recoveryJournalStore.create(operationID: operationID)
        }
        try recoveryJournalStore.update { journal in
            journal.virtualDisplayResource = ManagedResourceJournalRecord(
                instanceID: instanceID,
                resourceKind: "virtual-display",
                operationID: operationID,
                stage: .intent
            )
        }
        try failureInjector.check(.afterIntentJournal, resourceKind: "virtual-display")
        let capability = try capabilityStore.reserve(
            kind: .virtualDisplayHost,
            operationID: operationID,
            expectedExecutablePath: helperPath
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = [
            "internal-helper",
            InternalHelperKind.virtualDisplayHost.rawValue,
            capability.capabilityID,
            capability.nonce,
            capability.operationID,
            instanceID,
            String(resolution.width),
            String(resolution.height),
            String(refreshRate),
            scaleMode
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        let outputCollector = PipeTextCollector()
        let errorCollector = PipeTextCollector()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            outputCollector.append(data)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            errorCollector.append(data)
        }
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe
        try process.run()
        var runtimeCommitted = false
        do {
            try failureInjector.check(.afterProcessStart, resourceKind: "virtual-display")
        } catch {
            process.terminate()
            waitForProcessExit(process, timeoutSeconds: 1)
            try? recoveryJournalStore.update {
                $0.virtualDisplayResource?.stage = process.isRunning ? .cleanupPending : .cleaned
            }
            guard !process.isRunning else {
                throw CodexHeadlessError.managedResource(message: "Virtual host start failed and cleanup is unconfirmed. Recovery Journal was preserved.")
            }
            throw error
        }
        do {
            try recoveryJournalStore.update { $0.virtualDisplayResource?.stage = .started }
        } catch {
            inputPipe.fileHandleForWriting.closeFile()
            let cleanupConfirmed = stopLaunchedProcess(process, timeoutSeconds: 1)
            guard cleanupConfirmed else {
                throw CodexHeadlessError.managedResource(
                    message: "Virtual helper launched but its started stage could not be persisted and process cleanup is unconfirmed. Recovery Journal intent was preserved."
                )
            }
            throw error
        }

        let pid = process.processIdentifier
        logger.info("Started virtual display host PID \(pid).")

        let authorizationResult = waitForAuthorization(
            process: process,
            outputCollector: outputCollector,
            capabilityID: capability.capabilityID,
            operationID: operationID,
            instanceID: instanceID,
            timeoutSeconds: 1
        )
        guard authorizationResult == .authorized else {
            inputPipe.fileHandleForWriting.closeFile()
            let cleanupConfirmed = stopLaunchedProcess(process, timeoutSeconds: 1)
            try recoveryJournalStore.update {
                $0.virtualDisplayResource?.stage = cleanupConfirmed ? .cleaned : .cleanupPending
            }
            let error = helperLaunchError(
                result: authorizationResult,
                operationID: operationID,
                instanceID: instanceID,
                capabilityID: capability.capabilityID,
                process: process,
                stdout: outputCollector.snapshot(),
                stderr: errorCollector.snapshot(),
                startedAt: started
            )
            guard cleanupConfirmed else {
                throw CodexHeadlessError.managedResource(message: "\(error) Helper cleanup is unconfirmed; Recovery Journal was preserved.")
            }
            throw CodexHeadlessError.virtualDisplayOperation(message: error)
        }
        logger.info("[Helper] kind=virtual-display-host operation=\(shortID(operationID)) instance=\(shortID(instanceID)) phase=authorization result=accepted elapsedMs=\(Int((clock.uptime - started) * 1000))")

        let createdAt = clock.now
        let ownershipDeadline = clock.uptime + 0.5
        var processFacts = processInspector.facts(pid: pid)
        while (processFacts?.processStartTime == nil || processFacts?.executableFileIdentity == nil),
              clock.uptime < ownershipDeadline {
            clock.sleep(seconds: 0.02)
            processFacts = processInspector.facts(pid: pid)
        }
        guard let processFacts,
              processFacts.processStartTime != nil,
              processFacts.executableFileIdentity != nil else {
            process.terminate()
            waitForProcessExit(process, timeoutSeconds: 0.8)
            try recoveryJournalStore.update {
                $0.virtualDisplayResource?.stage = process.isRunning ? .cleanupPending : .cleaned
            }
            throw CodexHeadlessError.virtualDisplayOwnership(
                message: "Could not capture a complete start-time and executable identity for the new virtual display host."
            )
        }
        let ownership = ManagedProcessOwnershipRecord(
            instanceID: instanceID,
            pid: pid,
            executableCanonicalPath: processFacts.executableCanonicalPath,
            executableFileIdentity: processFacts.executableFileIdentity,
            processStartTime: processFacts.processStartTime,
            expectedCommandFragments: ["internal-helper", InternalHelperKind.virtualDisplayHost.rawValue, capability.capabilityID, instanceID],
            ownerOperationID: operationID,
            resourceKind: "virtual-display",
            createdAt: createdAt
        )
        let hostRecord = VirtualDisplayHostRecord(
            instanceID: instanceID,
            pid: pid,
            executablePath: helperPath,
            startedAt: createdAt,
            ownership: ownership
        )

        do {
            try failureInjector.check(.afterOwnershipObservation, resourceKind: "virtual-display")
            try launchJournalCoordinator.persistProvisionalHost(hostRecord, ownership: ownership)
        } catch {
            let cleanup = processInspector.terminate(
                ManagedProcessIdentity(
                    pid: pid,
                    executablePath: helperPath,
                    requiredCommandFragments: ownership.expectedCommandFragments,
                    expectedStartTime: ownership.processStartTime,
                    expectedExecutableFileIdentity: ownership.executableFileIdentity
                ),
                timeoutSeconds: 1.5
            )
            try? recoveryJournalStore.update { $0.virtualDisplayResource?.stage = cleanup.completed ? .cleaned : .cleanupPending }
            guard cleanup.completed else {
                throw CodexHeadlessError.managedResource(message: "Virtual ownership observation failed and cleanup is unconfirmed. Recovery Journal was preserved.")
            }
            throw error
        }

        let continuation = VirtualDisplayHelperProtocol.continueLine(
            capabilityID: capability.capabilityID,
            operationID: operationID,
            instanceID: instanceID
        ) + "\n"
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: Data(continuation.utf8))
        } catch {
            let cleanup = processInspector.terminate(
                ManagedProcessIdentity(
                    pid: pid,
                    executablePath: helperPath,
                    requiredCommandFragments: ownership.expectedCommandFragments,
                    expectedStartTime: ownership.processStartTime,
                    expectedExecutableFileIdentity: ownership.executableFileIdentity
                ),
                timeoutSeconds: 1.5
            )
            try recoveryJournalStore.update {
                $0.virtualDisplayResource?.stage = cleanup.completed ? .cleaned : .cleanupPending
            }
            guard cleanup.completed else {
                throw CodexHeadlessError.managedResource(
                    message: "Virtual helper continuation failed and cleanup is unconfirmed. Recovery Journal was preserved."
                )
            }
            throw CodexHeadlessError.virtualDisplayOperation(
                message: "Virtual helper exited before parent continuation: \(error.localizedDescription)"
            )
        }
        try? inputPipe.fileHandleForWriting.close()

        let launchResult = waitForNewDisplayID(
            beforeIDs: beforeIDs,
            timeoutSeconds: waitTimeoutSeconds,
            reportedIDExtraWaitSeconds: reportedIDExtraWaitSeconds,
            outputCollector: outputCollector,
            process: process,
            expectedInstanceID: instanceID,
            expectedHostIdentity: ManagedProcessIdentity(
                pid: pid,
                executablePath: helperPath,
                requiredCommandFragments: ownership.expectedCommandFragments,
                expectedStartTime: ownership.processStartTime,
                expectedExecutableFileIdentity: ownership.executableFileIdentity
            )
        )
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        guard case .ready(let displayID) = launchResult else {
            let cleanup = processInspector.terminate(
                ManagedProcessIdentity(
                    pid: pid,
                    executablePath: helperPath,
                    requiredCommandFragments: ownership.expectedCommandFragments,
                    expectedStartTime: ownership.processStartTime,
                    expectedExecutableFileIdentity: ownership.executableFileIdentity
                ),
                timeoutSeconds: 1.5
            )
            let displayStillPresent = displayManager.displays().contains { !beforeIDs.contains($0.id) && $0.isManagedVirtual }
            try recoveryJournalStore.update { journal in
                journal.virtualDisplayResource?.stage = cleanup.completed && !displayStillPresent ? .cleaned : .cleanupPending
                if cleanup.completed && !displayStillPresent { journal.virtualDisplayHost = nil }
            }
            let failure = helperLaunchError(
                result: launchResult,
                operationID: operationID,
                instanceID: instanceID,
                capabilityID: capability.capabilityID,
                process: process,
                stdout: outputCollector.snapshot(),
                stderr: errorCollector.snapshot(),
                startedAt: started
            )
            logger.warn(failure)
            guard cleanup.completed && !displayStillPresent else {
                throw CodexHeadlessError.managedResource(
                    message: "Virtual display creation failed and cleanup is unconfirmed. Recovery Journal was preserved."
                )
            }
            throw CodexHeadlessError.virtualDisplayOperation(message: failure)
        }

        do {
            try launchJournalCoordinator.persistReadyDisplay(displayID, host: hostRecord)
            try failureInjector.check(.afterObservedJournal, resourceKind: "virtual-display")
            try failureInjector.check(.beforeRuntimeCommit, resourceKind: "virtual-display")
            try stateStore.transaction { state in
                state.virtualDisplayCreated = true
                state.virtualDisplayPID = pid
                state.virtualDisplayID = displayID
                state.virtualDisplayRequestedResolution = resolution
                state.virtualDisplayRefreshRate = refreshRate
                state.virtualDisplayScaleMode = scaleMode
                state.virtualDisplayHost = hostRecord
            }
            runtimeCommitted = true
            try failureInjector.check(.afterRuntimeCommit, resourceKind: "virtual-display")
            try recoveryJournalStore.update { $0.virtualDisplayResource?.stage = .committed }
        } catch {
            let cleanup = processInspector.terminate(
                ManagedProcessIdentity(
                    pid: pid,
                    executablePath: helperPath,
                    requiredCommandFragments: ownership.expectedCommandFragments,
                    expectedStartTime: ownership.processStartTime,
                    expectedExecutableFileIdentity: ownership.executableFileIdentity
                ),
                timeoutSeconds: 1.5
            )
            let deadline = clock.uptime + 2
            while displayManager.display(id: displayID) != nil && clock.uptime < deadline { clock.sleep(seconds: 0.1) }
            let disappeared = displayManager.display(id: displayID) == nil
            try compensateFailedStart(
                record: hostRecord,
                runtimeCommitted: runtimeCommitted,
                cleanup: cleanup,
                displayDisappeared: disappeared
            )
            throw error
        }

        logger.info("Software virtual display created: displayID=\(displayID), PID=\(pid), resolution=\(resolution), scaleMode=\(scaleMode).")
        return displayID
    }

    public func reconcileManagedVirtualDisplayIfNeeded() {
        reconcileManagedVirtualDisplayIfNeeded(displays: displayManager.displays())
    }

    public func reconcileManagedVirtualDisplayIfNeeded(displays suppliedDisplays: [DisplayInfo]) {
        guard let state = try? stateStore.read() else {
            logger.error("Managed virtual display reconcile skipped because runtime state is unavailable.")
            return
        }
        guard state.virtualDisplayCreated,
              let pid = state.virtualDisplayPID,
              let record = state.virtualDisplayHost,
              let journal = try? recoveryJournalStore.read(),
              let trusted = journal.virtualDisplayHost,
              trusted.instanceID == record.instanceID,
              trusted.ownership == record.ownership,
              journal.virtualDisplayResource?.operationID == record.ownership?.ownerOperationID,
              processInspector.matches(ManagedProcessIdentity(
                pid: pid,
                executablePath: record.executablePath,
                requiredCommandFragments: record.ownership?.expectedCommandFragments ?? [],
                expectedStartTime: record.ownership?.processStartTime,
                expectedExecutableFileIdentity: record.ownership?.executableFileIdentity
              )) else {
            return
        }

        if let displayID = state.virtualDisplayID,
           suppliedDisplays.contains(where: { $0.id == displayID }) {
            return
        }

        let managedDisplays = suppliedDisplays.filter { $0.isManagedVirtual }
        guard managedDisplays.count == 1,
              let display = managedDisplays.first,
              journal.virtualDisplayResource?.displayID == nil
                || journal.virtualDisplayResource?.displayID == display.id else {
            return
        }

        do {
            try stateStore.transaction { newState in
                newState.virtualDisplayID = display.id
            }
            logger.info("Managed software virtual display reconciled: displayID=\(display.id), PID=\(pid).")
        } catch {
            logger.error("Managed virtual display ID reconciliation failed: \(error.localizedDescription)")
        }
    }

    public func destroyVirtualDisplayIfManaged() -> ManagedResourceCleanupResult {
        let started = clock.uptime
        defer { logger.info("[Perf] virtual-display-stop durationMs=\(Int((clock.uptime - started) * 1000))") }
        let state: RuntimeState
        let journal: RecoveryJournal?
        do {
            state = try stateStore.read()
            journal = try recoveryJournalStore.read()
        } catch {
            return .failed(reason: "Runtime state or Recovery Journal is unavailable: \(error.localizedDescription)")
        }
        var cleanup: ManagedResourceCleanupResult = .alreadyStopped
        let effectiveRecord = journal?.virtualDisplayHost ?? state.virtualDisplayHost
        let effectiveDisplayID = journal?.virtualDisplayResource?.displayID ?? state.virtualDisplayID
        do {
            try failureInjector.check(.beforeCleanup, resourceKind: "virtual-display")
        } catch {
            return .failed(reason: error.localizedDescription)
        }

        if let record = effectiveRecord,
           !trustedRecordMatchesState(record, state: state) {
            return .ownershipMismatch(reason: "Recovery journal does not independently verify virtual display instance \(record.instanceID).")
        }

        if let record = effectiveRecord {
            let pid = record.pid
            if processInspector.isRunning(pid: pid) {
                if processInspector.matches(ManagedProcessIdentity(
                    pid: pid,
                    executablePath: record.executablePath,
                    requiredCommandFragments: record.ownership?.expectedCommandFragments ?? [],
                    expectedStartTime: record.ownership?.processStartTime,
                    expectedExecutableFileIdentity: record.ownership?.executableFileIdentity
                )) {
                    cleanup = processInspector.terminate(
                        ManagedProcessIdentity(
                            pid: pid,
                            executablePath: record.executablePath,
                            requiredCommandFragments: record.ownership?.expectedCommandFragments
                                ?? ["internal-helper", InternalHelperKind.virtualDisplayHost.rawValue, record.instanceID],
                            expectedStartTime: record.ownership?.processStartTime,
                            expectedExecutableFileIdentity: record.ownership?.executableFileIdentity
                        ),
                        timeoutSeconds: 1.5
                    )
                } else {
                    cleanup = .ownershipMismatch(reason: "Virtual display host PID \(pid) does not match its recorded instance.")
                }
            } else {
                cleanup = .alreadyStopped
            }
        } else {
            logger.info("No managed software virtual display PID in state.")
            cleanup = .alreadyStopped
        }

        guard cleanup.completed else {
            logger.error("Managed virtual display cleanup \(cleanup.summary); recorded state was preserved.")
            return cleanup
        }
        do {
            try failureInjector.check(.afterTerminateRequest, resourceKind: "virtual-display")
        } catch {
            return .failed(reason: error.localizedDescription)
        }
        let disappearanceDeadline = clock.uptime + 2
        while managedDisplayStillPresent(displayID: effectiveDisplayID), clock.uptime < disappearanceDeadline {
            clock.sleep(seconds: 0.1)
        }
        if managedDisplayStillPresent(displayID: effectiveDisplayID) {
            return .failed(reason: "Host exited but managed virtual display is still enumerated.")
        }
        if let pid = effectiveRecord?.pid, processInspector.isRunning(pid: pid) {
            return .failed(reason: "Virtual display host PID \(pid) is still running after cleanup.")
        }
        do {
            try failureInjector.check(.afterResourceDisappearCheck, resourceKind: "virtual-display")
        } catch {
            return .failed(reason: error.localizedDescription)
        }
        do {
            try stateStore.transaction { state in Self.clearManagedHostState(&state) }
            if journal != nil {
                try recoveryJournalStore.update { journal in
                    journal.virtualDisplayHost = nil
                    journal.virtualDisplayResource?.stage = .cleaned
                    journal.cleanupProgress.virtualDisplayCleanup = .completed
                    journal.cleanupProgress.virtualHostStop = .completed
                    journal.cleanupProgress.virtualDisplayDisappearance = .completed
                }
            }
            try StandaloneJournalFinalizer(
                stateStore: stateStore,
                journalStore: recoveryJournalStore,
                snapshotProvider: snapshotProvider
            ).finalizeIfClean()
            logger.info("Managed virtual display cleanup \(cleanup.summary).")
            return cleanup
        } catch {
            return .failed(reason: "Resource stopped but state cleanup failed: \(error.localizedDescription)")
        }
    }

    public func possibleOrphanHostProcessIDs() -> [Int32] {
        let recordedPID = (try? stateStore.read().virtualDisplayPID) ?? nil
        let snapshot = snapshotProvider.capture()
        guard snapshot.succeeded else { return [] }
        guard case .verified(let pid) = HelperProcessCandidateDetector.verify(
            snapshot: snapshot, kind: .virtualDisplayHost, inspector: processInspector
        ), pid != recordedPID else { return [] }
        return [pid]
    }

    public func recoveryHostRecord() -> VirtualDisplayHostRecord? {
        guard let journal = try? recoveryJournalStore.read(),
              let record = journal.virtualDisplayHost,
              processInspector.matches(ManagedProcessIdentity(
                pid: record.pid,
                executablePath: record.executablePath,
                requiredCommandFragments: record.ownership?.expectedCommandFragments ?? [],
                expectedStartTime: record.ownership?.processStartTime,
                expectedExecutableFileIdentity: record.ownership?.executableFileIdentity
              )) else { return nil }
        return record
    }

    public func managedResourceObservation(snapshot suppliedSnapshot: ManagedProcessSnapshot? = nil) -> ManagedResourceObservation {
        do {
            if let journal = try recoveryJournalStore.read(), let record = journal.virtualDisplayHost {
                let identity = ManagedProcessIdentity(
                    pid: record.pid,
                    executablePath: record.executablePath,
                    requiredCommandFragments: record.ownership?.expectedCommandFragments ?? [],
                    expectedStartTime: record.ownership?.processStartTime,
                    expectedExecutableFileIdentity: record.ownership?.executableFileIdentity
                )
                if processInspector.matches(identity) {
                    return .init(status: .verifiedOwned, summary: "virtual display host identity matches Recovery Journal", pid: record.pid)
                }
                if processInspector.isRunning(pid: record.pid) {
                    return .init(status: .unknown, summary: "recorded virtual host PID has mismatched ownership", pid: record.pid)
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
            snapshot: snapshot, kind: .virtualDisplayHost, inspector: processInspector
        ) {
        case .verified(let pid):
            return .init(status: .possibleOwned, summary: "virtual display helper process exists without verified ownership", pid: pid)
        case .unknown(let pid, let reason):
            return .init(status: .unknown, summary: reason, pid: pid)
        case .none:
            break
        }
        if displayManager.displays().contains(where: { $0.isManagedVirtual }) {
            return .init(status: .unknown, summary: "managed virtual display is enumerated without a verified host")
        }
        return .none
    }

    private func activeManagedVirtualDisplayID() -> UInt32? {
        guard let state = try? stateStore.read() else { return nil }
        guard let record = state.virtualDisplayHost,
              let journal = try? recoveryJournalStore.read(),
              let trusted = journal.virtualDisplayHost,
              trusted.instanceID == record.instanceID,
              trusted.ownership == record.ownership,
              let ownership = record.ownership,
              journal.virtualDisplayResource?.operationID == ownership.ownerOperationID,
              processInspector.matches(ManagedProcessIdentity(
                pid: record.pid,
                executablePath: record.executablePath,
                requiredCommandFragments: ownership.expectedCommandFragments,
                expectedStartTime: ownership.processStartTime,
                expectedExecutableFileIdentity: ownership.executableFileIdentity
              )),
              let displayID = state.virtualDisplayID,
              displayManager.displays().contains(where: { $0.id == displayID && $0.isManagedVirtual }) else {
            return nil
        }
        return displayID
    }

    func waitForAuthorization(
        process: Process,
        outputCollector: PipeTextCollector,
        capabilityID: String,
        operationID: String,
        instanceID: String,
        timeoutSeconds: TimeInterval
    ) -> VirtualDisplayAuthorizationWaitResult {
        let deadline = clock.uptime + timeoutSeconds
        while clock.uptime < deadline {
            let authorizationEvents = outputCollector.events().compactMap { event -> (String, String, String)? in
                guard case .authorized(_, let capability, let operation, let instance) = event else { return nil }
                return (capability, operation, instance)
            }
            if authorizationEvents.count > 1 {
                return .invalidHandshake("duplicate authorization event")
            }
            if let event = authorizationEvents.first {
                guard event.0 == capabilityID,
                      event.1 == operationID,
                      event.2 == instanceID else {
                    return .invalidHandshake("authorization identifiers did not match the launch request")
                }
                return .authorized
            }
            if !process.isRunning {
                return .helperExited(
                    exitCode: process.terminationStatus,
                    reason: process.terminationReason == .exit ? "exit" : "signal"
                )
            }
            clock.sleep(seconds: 0.02)
        }
        return .timedOut
    }

    func waitForNewDisplayID(
        beforeIDs: Set<UInt32>,
        timeoutSeconds: TimeInterval,
        reportedIDExtraWaitSeconds: TimeInterval,
        outputCollector: PipeTextCollector,
        process: Process,
        expectedInstanceID: String,
        expectedHostIdentity: ManagedProcessIdentity? = nil
    ) -> VirtualDisplayLaunchWaitResult {
        _ = beforeIDs // Retained in the testable launch API; unrelated new displays are intentionally ignored.
        var deadline = clock.uptime + timeoutSeconds
        var reportedDisplayID: UInt32?
        while clock.uptime < deadline {
            let readyEvents = outputCollector.events().compactMap { event -> (String, UInt32)? in
                guard case .ready(let instance, let displayID) = event else { return nil }
                return (instance, displayID)
            }
            if readyEvents.count > 1 {
                return .invalidHandshake("duplicate display-ready event")
            }
            if let ready = readyEvents.first {
                guard ready.0 == expectedInstanceID else {
                    return .invalidHandshake("display-ready instance identifier did not match the launch request")
                }
                reportedDisplayID = ready.1
            }
            if let expectedDisplayID = reportedDisplayID {
                if let display = displayManager.display(id: expectedDisplayID) {
                    guard display.isManagedVirtual else {
                        return .invalidHandshake("reported display ID does not identify a CodexHeadless managed virtual display")
                    }
                    guard readyHostIsStable(process),
                          expectedHostIdentity.map(processInspector.matches) ?? true else {
                        return .helperExited(exitCode: process.terminationStatus, reason: "host ownership was not stable after display-ready")
                    }
                    return .ready(displayID: expectedDisplayID)
                }
                if deadline - clock.uptime > reportedIDExtraWaitSeconds {
                    stateStore.bestEffortUpdate { state in
                        state.phase = .acceptingReportedVirtualDisplayID
                        state.phaseMessage = RuntimePhase.acceptingReportedVirtualDisplayID.message
                        state.phaseStartedAt = clock.now
                        state.phaseDeadlineAt = clock.now.addingTimeInterval(reportedIDExtraWaitSeconds)
                        state.lastProgressAt = clock.now
                    }
                    deadline = clock.uptime + reportedIDExtraWaitSeconds
                    logger.info("[Phase] acceptingReportedVirtualDisplayID, displayID=\(expectedDisplayID), extraWait=\(Int(reportedIDExtraWaitSeconds))s")
                }
            }
            if !process.isRunning {
                return .helperExited(
                    exitCode: process.terminationStatus,
                    reason: process.terminationReason == .exit ? "exit before display-ready" : "signal before display-ready"
                )
            }
            clock.sleep(seconds: 0.15)
        }
        return .displayTimedOut(reportedDisplayID: reportedDisplayID)
    }

    private func readyHostIsStable(_ process: Process) -> Bool {
        guard process.isRunning else { return false }
        clock.sleep(seconds: 0.05)
        return process.isRunning
    }

    private func waitForProcessExit(_ process: Process, timeoutSeconds: TimeInterval) {
        let deadline = clock.uptime + timeoutSeconds
        while process.isRunning && clock.uptime < deadline {
            clock.sleep(seconds: 0.05)
        }
    }

    private func waitForProcessExit(pid: Int32, timeoutSeconds: TimeInterval) {
        let deadline = clock.uptime + timeoutSeconds
        while processInspector.isRunning(pid: pid) && clock.uptime < deadline {
            clock.sleep(seconds: 0.05)
        }
    }

    private func processDiagnostics(process: Process, stdout: String, stderr: String) -> String {
        let termination: String
        if process.isRunning {
            termination = "running"
        } else {
            termination = "\(process.terminationReason == .exit ? "exit" : "signal"):\(process.terminationStatus)"
        }

        let stdoutText = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrText = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "termination=\(termination), stdout=\(stdoutText.isEmpty ? "<empty>" : stdoutText), stderr=\(stderrText.isEmpty ? "<empty>" : stderrText)"
    }

    private func stopLaunchedProcess(_ process: Process, timeoutSeconds: TimeInterval) -> Bool {
        if process.isRunning { process.terminate() }
        waitForProcessExit(process, timeoutSeconds: timeoutSeconds)
        return !process.isRunning
    }

    private func helperLaunchError(
        result: VirtualDisplayAuthorizationWaitResult,
        operationID: String,
        instanceID: String,
        capabilityID: String,
        process: Process,
        stdout: String,
        stderr: String,
        startedAt: TimeInterval
    ) -> String {
        let phase: String
        let detail: String
        switch result {
        case .authorized:
            phase = "authorization"; detail = "unexpected authorized result"
        case .helperExited(let code, let reason):
            phase = "authorization"; detail = "helper exited code=\(code) reason=\(reason)"
        case .timedOut:
            phase = "authorization"; detail = "authorization timed out"
        case .invalidHandshake(let reason):
            phase = "authorization"; detail = reason
        }
        return helperDiagnostic(
            phase: phase, detail: detail, operationID: operationID, instanceID: instanceID,
            capabilityID: capabilityID, process: process, stdout: stdout, stderr: stderr, startedAt: startedAt
        )
    }

    private func helperLaunchError(
        result: VirtualDisplayLaunchWaitResult,
        operationID: String,
        instanceID: String,
        capabilityID: String,
        process: Process,
        stdout: String,
        stderr: String,
        startedAt: TimeInterval
    ) -> String {
        let detail: String
        switch result {
        case .ready:
            detail = "unexpected ready result"
        case .helperExited(let code, let reason):
            detail = "helper exited code=\(code) reason=\(reason)"
        case .displayTimedOut(let displayID):
            detail = "display timed out reportedDisplayID=\(displayID.map(String.init) ?? "none")"
        case .invalidHandshake(let reason):
            detail = reason
        }
        return helperDiagnostic(
            phase: "display-ready", detail: detail, operationID: operationID, instanceID: instanceID,
            capabilityID: capabilityID, process: process, stdout: stdout, stderr: stderr, startedAt: startedAt
        )
    }

    private func helperDiagnostic(
        phase: String,
        detail: String,
        operationID: String,
        instanceID: String,
        capabilityID: String,
        process: Process,
        stdout: String,
        stderr: String,
        startedAt: TimeInterval
    ) -> String {
        let stderrText = sanitizedDiagnostic(stderr)
        return "[Helper] kind=virtual-display-host operation=\(shortID(operationID)) instance=\(shortID(instanceID)) capability=\(shortID(capabilityID)) phase=\(phase) exit=\(process.isRunning ? "running" : String(process.terminationStatus)) termination=\(process.isRunning ? "running" : (process.terminationReason == .exit ? "exit" : "signal")) elapsedMs=\(Int((clock.uptime - startedAt) * 1000)) error=\"\(sanitizedDiagnostic(detail))\" stderr=\"\(stderrText.isEmpty ? "<empty>" : stderrText)\""
    }

    private func shortID(_ value: String) -> String { String(value.prefix(8)) }

    private func sanitizedDiagnostic(_ value: String) -> String {
        String(value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\"", with: "'")
            .prefix(500))
    }

    func compensateFailedStart(
        record: VirtualDisplayHostRecord,
        runtimeCommitted: Bool,
        cleanup: ManagedResourceCleanupResult,
        displayDisappeared: Bool
    ) throws {
        guard cleanup.completed && displayDisappeared else {
            try? recoveryJournalStore.update { $0.virtualDisplayResource?.stage = .cleanupPending }
            throw CodexHeadlessError.managedResource(
                message: "Virtual display commit failed and cleanup is unconfirmed. Recovery Journal was preserved."
            )
        }
        if runtimeCommitted {
            do {
                try stateStore.transaction { state in Self.clearManagedHostState(&state) }
            } catch let compensationError {
                try? recoveryJournalStore.update { $0.virtualDisplayResource?.stage = .cleanupPending }
                throw CodexHeadlessError.managedResource(
                    message: "Virtual display stopped, but RuntimeState compensation failed: \(compensationError.localizedDescription). Recovery Journal ownership was preserved."
                )
            }
        }
        try recoveryJournalStore.update { journal in
            journal.virtualDisplayResource?.stage = .cleaned
            journal.virtualDisplayHost = nil
        }
    }

    private func hostProcessMatchesRecordedInstance(state: RuntimeState, pid: Int32) -> Bool {
        guard let record = state.virtualDisplayHost else {
            return false
        }
        guard record.pid == pid else { return false }
        return processInspector.matches(ManagedProcessIdentity(
            pid: pid,
            executablePath: record.executablePath,
            requiredCommandFragments: record.ownership?.expectedCommandFragments
                ?? ["internal-helper", InternalHelperKind.virtualDisplayHost.rawValue, record.instanceID],
            expectedStartTime: record.ownership?.processStartTime,
            expectedExecutableFileIdentity: record.ownership?.executableFileIdentity
        ))
    }

    private func trustedRecordMatchesState(_ record: VirtualDisplayHostRecord, state: RuntimeState) -> Bool {
        guard record.ownership != nil else { return false }
        guard let journal = try? recoveryJournalStore.read(),
              let trusted = journal.virtualDisplayHost,
              let stateRecord = state.virtualDisplayHost else { return false }
        return trusted.instanceID == record.instanceID
            && trusted.pid == record.pid
            && trusted.ownership == record.ownership
            && stateRecord.instanceID == record.instanceID
            && stateRecord.pid == record.pid
            && stateRecord.ownership == record.ownership
            && journal.virtualDisplayResource?.operationID == record.ownership?.ownerOperationID
    }

    private func managedDisplayStillPresent(displayID: UInt32?) -> Bool {
        if let displayID,
           displayManager.display(id: displayID) != nil { return true }
        return displayManager.displays().contains(where: { $0.isManagedVirtual })
    }

    private static func clearManagedHostState(_ state: inout RuntimeState) {
        state.virtualDisplayCreated = false
        state.virtualDisplayPID = nil
        state.virtualDisplayID = nil
        state.virtualDisplayRequestedResolution = nil
        state.virtualDisplayRefreshRate = nil
        state.virtualDisplayScaleMode = nil
        state.virtualDisplayHost = nil
    }
}

final class PipeTextCollector {
    private let lock = NSLock()
    private var text = ""

    func append(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else {
            return
        }
        lock.lock()
        text += chunk
        lock.unlock()
    }

    func displayID() -> UInt32? {
        let snapshot = snapshot()

        guard let range = snapshot.range(of: #"displayID=(\d+)"#, options: .regularExpression) else {
            return nil
        }

        let match = snapshot[range]
        guard let value = match.split(separator: "=").last else {
            return nil
        }
        return UInt32(value)
    }

    func events() -> [VirtualDisplayHelperEvent] {
        VirtualDisplayHelperProtocol.parseEvents(snapshot())
    }

    func snapshot() -> String {
        lock.lock()
        let snapshot = text
        lock.unlock()
        return snapshot
    }
}

public enum VirtualDisplayHost {
    private typealias AllocFunction = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?
    private typealias InitWithDescriptorFunction = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
    private typealias InitModeFunction = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> Unmanaged<AnyObject>?
    private typealias ApplySettingsFunction = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
    private typealias DisplayIDFunction = @convention(c) (AnyObject, Selector) -> UInt32

    public static func run(
        resolution: Resolution,
        refreshRate: Int,
        scaleMode: String,
        instanceID: String
    ) throws -> Never {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay"),
              let modeClass = NSClassFromString("CGVirtualDisplayMode"),
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type else {
            throw CodexHeadlessError.virtualDisplayOperation(message: "CGVirtualDisplay runtime classes are unavailable.")
        }

        let descriptor = descriptorClass.init()
        descriptor.setValue("CodexHeadless Virtual Display", forKey: "name")
        descriptor.setValue(NSNumber(value: UInt32(0xC0DE)), forKey: "vendorID")
        descriptor.setValue(NSNumber(value: UInt32(0x0511)), forKey: "productID")
        descriptor.setValue(NSNumber(value: UInt32(1)), forKey: "serialNum")
        descriptor.setValue(NSNumber(value: UInt32(resolution.width)), forKey: "maxPixelsWide")
        descriptor.setValue(NSNumber(value: UInt32(resolution.height)), forKey: "maxPixelsHigh")
        descriptor.setValue(NSValue(size: CGSize(width: 300, height: 170)), forKey: "sizeInMillimeters")

        guard let displayAllocated = allocObject(displayClass)?.takeRetainedValue() else {
            throw CodexHeadlessError.virtualDisplayOperation(message: "Failed to allocate CGVirtualDisplay.")
        }
        guard let display = initWithDescriptor(displayAllocated, descriptor: descriptor)?.takeRetainedValue() else {
            throw CodexHeadlessError.virtualDisplayOperation(message: "Failed to initialize CGVirtualDisplay.")
        }

        guard let modeAllocated = allocObject(modeClass)?.takeRetainedValue() else {
            throw CodexHeadlessError.virtualDisplayOperation(message: "Failed to allocate CGVirtualDisplayMode.")
        }
        guard let mode = initMode(
            modeAllocated,
            width: UInt32(resolution.width),
            height: UInt32(resolution.height),
            refreshRate: Double(refreshRate)
        )?.takeRetainedValue() else {
            throw CodexHeadlessError.virtualDisplayOperation(message: "Failed to initialize CGVirtualDisplayMode.")
        }

        let settings = settingsClass.init()
        settings.setValue([mode], forKey: "modes")
        let hiDPI = scaleMode.lowercased() == "hidpi" ? UInt32(1) : UInt32(0)
        settings.setValue(NSNumber(value: hiDPI), forKey: "hiDPI")
        settings.setValue(NSNumber(value: UInt32(0)), forKey: "rotation")

        guard applySettings(display, settings: settings) else {
            throw CodexHeadlessError.virtualDisplayOperation(message: "Failed to apply CGVirtualDisplay settings.")
        }

        let displayID = getDisplayID(display)
        let protocolLine = VirtualDisplayHelperProtocol.readyLine(instanceID: instanceID, displayID: displayID)
        FileHandle.standardOutput.write(Data((protocolLine + "\ndisplayID=\(displayID)\n").utf8))
        try? FileHandle.standardOutput.synchronize()

        signal(SIGTERM) { _ in exit(0) }
        signal(SIGINT) { _ in exit(0) }
        RunLoop.current.run()
        fatalError("RunLoop unexpectedly returned.")
    }

    private static func objcMsgSendSymbol() -> UnsafeMutableRawPointer {
        dlsym(dlopen(nil, RTLD_LAZY), "objc_msgSend")
    }

    private static func allocObject(_ cls: AnyClass) -> Unmanaged<AnyObject>? {
        let function = unsafeBitCast(objcMsgSendSymbol(), to: AllocFunction.self)
        return function(cls, NSSelectorFromString("alloc"))
    }

    private static func initWithDescriptor(_ object: AnyObject, descriptor: AnyObject) -> Unmanaged<AnyObject>? {
        let function = unsafeBitCast(objcMsgSendSymbol(), to: InitWithDescriptorFunction.self)
        return function(object, NSSelectorFromString("initWithDescriptor:"), descriptor)
    }

    private static func initMode(_ object: AnyObject, width: UInt32, height: UInt32, refreshRate: Double) -> Unmanaged<AnyObject>? {
        let function = unsafeBitCast(objcMsgSendSymbol(), to: InitModeFunction.self)
        return function(object, NSSelectorFromString("initWithWidth:height:refreshRate:"), width, height, refreshRate)
    }

    private static func applySettings(_ display: AnyObject, settings: AnyObject) -> Bool {
        let function = unsafeBitCast(objcMsgSendSymbol(), to: ApplySettingsFunction.self)
        return function(display, NSSelectorFromString("applySettings:"), settings)
    }

    private static func getDisplayID(_ display: AnyObject) -> UInt32 {
        let function = unsafeBitCast(objcMsgSendSymbol(), to: DisplayIDFunction.self)
        return function(display, NSSelectorFromString("displayID"))
    }
}
