import Darwin
import Foundation

public final class Doctor {
    private let configManager: ConfigManaging
    private let stateStore: RuntimeStateStoring
    private let displayManager: DisplayManaging
    private let builtInDisplayManager: BuiltInDisplayManaging
    private let virtualDisplayManager: VirtualDisplayManager
    private let processInspector: ManagedProcessInspecting
    private let recoveryJournalStore: RecoveryJournalStoring
    private let sleepManager: SleepManaging

    public init(
        configManager: ConfigManaging = ConfigManager(),
        stateStore: RuntimeStateStoring = StateStore(),
        displayManager: DisplayManaging = DisplayManager(),
        builtInDisplayManager: BuiltInDisplayManaging = BuiltInDisplayManager(),
        virtualDisplayManager: VirtualDisplayManager? = nil,
        processInspector: ManagedProcessInspecting = ManagedProcessInspector(),
        recoveryJournalStore: RecoveryJournalStoring = RecoveryJournalStore(),
        sleepManager: SleepManaging? = nil
    ) {
        self.configManager = configManager
        self.stateStore = stateStore
        self.displayManager = displayManager
        self.builtInDisplayManager = builtInDisplayManager
        self.virtualDisplayManager = virtualDisplayManager ?? VirtualDisplayManager(
            stateStore: stateStore,
            displayManager: displayManager,
            recoveryJournalStore: recoveryJournalStore
        )
        self.processInspector = processInspector
        self.recoveryJournalStore = recoveryJournalStore
        self.sleepManager = sleepManager ?? SleepManager(
            stateStore: stateStore,
            configManager: configManager,
            recoveryJournalStore: recoveryJournalStore
        )
    }

    public func report() -> String {
        let config = configManager.load()
        let journalResult = Result { try recoveryJournalStore.read() }
        let journal = try? journalResult.get()
        let virtualDisplayPolicy = VirtualDisplayPolicy.effectivePolicy(for: config.virtualDisplay)
        let state = stateStore.load()
        let displays = displayManager.displays()
        let builtIn = displays.first { $0.isBuiltIn }
        let managedVirtual = state.virtualDisplayID.flatMap { id in
            displays.first { $0.id == id }
        }
        let observedManagedVirtual = managedVirtual ?? displays.first { $0.isManagedVirtual }
        let external = displays.first { display in
            !display.isBuiltIn
                && display.isActive
                && display.isOnline
                && display.id != state.virtualDisplayID
        }
        let main = displays.first { $0.isMain }
        let keepAwakeObserved = state.keepAwakeHost.flatMap { record -> Bool? in
            guard let pid = record.pid, record.backend == .caffeinate else { return nil }
            return processInspector.matches(ManagedProcessIdentity(
                pid: pid,
                executablePath: record.executablePath ?? "codex-headless",
                requiredCommandFragments: record.ownership?.expectedCommandFragments
                    ?? ["internal-helper", InternalHelperKind.keepAwakeHost.rawValue, record.instanceID],
                expectedStartTime: record.ownership?.processStartTime,
                expectedExecutableFileIdentity: record.ownership?.executableFileIdentity
            ))
        }
        let caffeinateText = state.caffeinatePID.map { pid in
            keepAwakeObserved == true ? "Owned and running (PID \(pid))" : "Missing or ownership mismatch (PID \(pid))"
        } ?? "Not recorded"
        let keepAwakeDrift = state.keepAwake && keepAwakeObserved == false
        let virtualDisplayDrift = state.virtualDisplayCreated != (observedManagedVirtual != nil)
            || (state.virtualDisplayID != nil && managedVirtual == nil)
        let mainText = main.map { display -> String in
            if display.id == state.virtualDisplayID {
                return "Managed Virtual"
            }
            return display.isBuiltIn ? "Built-in" : "External / Dummy"
        } ?? "Unknown"
        let virtualDisplayText = observedManagedVirtual.map {
            "ID \($0.id), \($0.width)x\($0.height), main=\($0.isMain ? "yes" : "no")"
        } ?? "Not active"
        let orphanHostCount = virtualDisplayManager.possibleOrphanHostProcessIDs().count
        let cleanNormal = CleanNormalAssessor(
            stateStore: stateStore,
            recoveryJournalStore: recoveryJournalStore,
            sleepManager: sleepManager,
            virtualDisplayManager: virtualDisplayManager,
            displayManager: displayManager
        ).assess()
        let journalError: String?
        switch journalResult {
        case .success: journalError = nil
        case .failure(let error): journalError = error.localizedDescription
        }
        let operationalEvidence = state.mode == .normal ? nil : OperationalEvidenceAssessor(
            stateStore: stateStore, journalStore: recoveryJournalStore,
            sleepManager: sleepManager, virtualManager: virtualDisplayManager,
            displayManager: displayManager
        ).assess(state: state, source: .explicitDoctor)
        let operational = state.mode == .normal
            ? OperationalSafetyPresentation.makeNormal(cleanNormal)
            : OperationalSafetyPresentation.make(state: state, availability: operationalEvidence.map(OperationalEvidenceAvailability.fresh) ?? .unavailable(journalError))

        return """
        CodexHeadless Doctor
        --------------------
        Overall: \(overallStatus(external: external, managedVirtual: managedVirtual, policy: virtualDisplayPolicy))

        Runtime:
          Mode: \(state.mode.rawValue)
          Operational Safety: \(operational.title)
          Operational Evidence Source: \(operationalEvidence?.source.rawValue ?? "Not applicable")
          Operational Journal: \(operationalEvidence.map { String(describing: $0.journal) } ?? "Not applicable")
          Operational Process Snapshot: \(operationalEvidence.map { String(describing: $0.processSnapshot) } ?? "Not applicable")
          Operational Keep Awake Owner: \(operationalEvidence?.keepAwake.status.rawValue ?? "Not applicable")
          Operational Virtual Owner: \(operationalEvidence?.virtualDisplay.status.rawValue ?? "Not applicable")
          Operational Display ID: expected=\(operationalEvidence?.display.expectedManagedDisplayID.map(String.init) ?? "none"), observed=\(operationalEvidence?.display.observedManagedDisplayID.map(String.init) ?? "none")
          Operational Violations: \(operationalEvidence.map { String(describing: $0.violations) } ?? "Not applicable")
          Normal Readiness: \(operational.normalReadinessText)
          Violations: \(cleanNormal.violations.isEmpty ? "None" : cleanNormal.violations.joined(separator: " | "))
          Recommended Action: \(operational.recommendedAction)
          Phase: \(RuntimePhaseFormatter.phase(state).rawValue)
          Current Step: \(RuntimePhaseFormatter.message(state))
          Rollback: \(state.rollbackConfirmed ? "Confirmed" : "Pending")

        Files:
          Config: \(fileStatus(CodexHeadlessPaths.configFile))
          State: \(fileStatus(CodexHeadlessPaths.stateFile))
          Recovery Journal: \(journalFileStatus(result: journalResult))
          Log: \(fileStatus(CodexHeadlessPaths.logFile))

        Recovery Journal:
          Active: \(journal != nil ? "Yes" : "No")
          Operation: \(journal?.operationID ?? "None")
          Stage: \(journal?.stage.rawValue ?? "None")
          Physical takeover verified: \(journal?.cleanupProgress.physicalTakeoverVerified == true ? "Yes" : "No")
          Brightness restore: \(journal?.cleanupProgress.brightnessRestore.rawValue ?? "None")
          Brightness verification: \(journal?.cleanupProgress.brightnessVerification?.rawValue ?? "None")
          Virtual host stop: \(journal?.cleanupProgress.virtualHostStop?.rawValue ?? "None")
          Virtual display disappearance: \(journal?.cleanupProgress.virtualDisplayDisappearance?.rawValue ?? "None")
          Keep Awake holder stop: \(journal?.cleanupProgress.keepAwakeHolderStop?.rawValue ?? "None")
          Keep Awake assertion disappearance: \(journal?.cleanupProgress.keepAwakeAssertionDisappearance?.rawValue ?? "None")
          Touch Bar restore: \(journal?.cleanupProgress.touchBarRestore.rawValue ?? "None")
          RuntimeState persistence: \(journal?.cleanupProgress.runtimeStatePersistence?.rawValue ?? "None")
          Journal finalization: \(journal?.cleanupProgress.journalFinalization?.rawValue ?? "None")

        Displays:
          Count: \(displays.count)
          Note: \(displays.isEmpty ? "No displays visible to this process; run from the target GUI login session if this looks wrong." : "Display enumeration available.")
          Built-in: \(builtIn.map { "\($0.width)x\($0.height), main=\($0.isMain ? "yes" : "no")" } ?? "Not detected")
          External / Dummy: \(external.map { "ID \($0.id), \($0.width)x\($0.height), main=\($0.isMain ? "yes" : "no")" } ?? "Not detected")
          Managed Virtual: \(virtualDisplayText)
          Main: \(mainText)

        Virtual Display:
          Policy: \(virtualDisplayPolicy.rawValue)
          Recorded Active: \(state.virtualDisplayCreated ? "Yes" : "No")
          Observed Active: \(observedManagedVirtual != nil ? "Yes" : "No")
          Drift: \(virtualDisplayDrift ? "Yes" : "No")
          Requested: \(state.virtualDisplayCreated ? "\(state.virtualDisplayRequestedResolution ?? config.virtualDisplay.resolution) @ \(state.virtualDisplayRefreshRate ?? config.virtualDisplay.refreshRate)Hz" : "Not active")
          Scale Mode: \(state.virtualDisplayCreated ? (state.virtualDisplayScaleMode ?? config.virtualDisplay.scaleMode) : config.virtualDisplay.scaleMode)
          Host PID: \(state.virtualDisplayPID.map(String.init) ?? "Not running")
          Possible Orphan Hosts: \(orphanHostCount)

        Keep Awake:
          Recorded State: \(state.keepAwake ? "On" : "Off")
          Observed Managed Process: \(keepAwakeObserved.map { $0 ? "On" : "Missing / Mismatch" } ?? "Not applicable")
          Drift: \(keepAwakeDrift ? "Yes" : "No")
          Backend: \(state.keepAwakeBackend ?? config.keepAwakeBackend?.rawValue ?? KeepAwakeBackend.caffeinate.rawValue)
          Assertion Holder: \(caffeinateText)
          pmset: Not modified by CodexHeadless

        Timing:
          Virtual display enumeration wait: \(config.effectiveTiming.virtualDisplayEnumerationWaitSeconds)s
          Reported ID extra wait: \(config.effectiveTiming.virtualDisplayReportedIDExtraWaitSeconds)s
          Soft-disconnect disappear wait: \(config.effectiveTiming.softDisconnectDisappearWaitSeconds)s
          Restore built-in short wait: \(config.effectiveTiming.restoreBuiltInShortWaitSeconds)s
          Restore physical display wait: \(config.effectiveTiming.restorePhysicalDisplayWaitSeconds)s
          Restore physical display grace: \(config.effectiveTiming.effectiveRestorePhysicalDisplayGraceSeconds)s
          Restore grace poll interval: \(config.effectiveTiming.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds)ms
          Restore post-promote stabilization: \(config.effectiveTiming.effectiveRestorePostPromoteStabilizationMilliseconds)ms
          Restore cooldown: \(config.effectiveTiming.restoreCooldownSeconds)s
          Restore paused cooldown: \(config.effectiveTiming.restoreCooldownAfterPausedSeconds)s

        Brightness Fallback:
          Original brightness readable: \(builtInDisplayManager.currentBrightness() == nil ? "No" : "Yes")
          Reversible fallback: \(builtInDisplayManager.brightnessCapability().available ? "Available" : "Unavailable")
          Policy: Reject before side effects when reversible read/restore is unavailable
          Last method: \(state.builtInBrightnessMethod ?? "None")

        Soft Disconnect:
          CoreDisplay SetUserDisabled: \(CoreDisplayPrivateBridge.shared.probe().setUserDisabledAvailable ? "Available" : "Unavailable")
          SkyLight MainConnection: \(CoreDisplayPrivateBridge.shared.probe().mainConnectionAvailable ? "Available" : "Unavailable")
          SkyLight ConfigureDisplayEnabled: \(CoreDisplayPrivateBridge.shared.probe().configureDisplayEnabledAvailable ? "Available" : "Unavailable")
          State: \(state.builtInSoftDisconnected == true ? "Soft-disconnected" : "Not soft-disconnected")
          Last method: \(state.builtInSoftDisconnectMethod ?? "None")
          Last message: \(state.builtInSoftDisconnectLastMessage ?? "None")
          Blocked reason: \(config.softDisconnectBlockedReason ?? "None")

        Touch Bar:
          Config: \(config.hideTouchBarInHeadless == true ? "Hide in Headless Mode" : "Do not hide")
          State: \(state.touchBarHidden == true ? "Hidden" : "Not hidden")
          Last method: \(state.touchBarHideMethod ?? "None")
          Last message: \(state.touchBarLastMessage ?? "None")

        Config:
          Virtual Display Policy: \(virtualDisplayPolicy.rawValue)
          Resolution: \(config.virtualDisplay.resolution)
          Scale Mode: \(config.virtualDisplay.scaleMode)
          Keep Awake Backend: \(config.keepAwakeBackend?.rawValue ?? KeepAwakeBackend.caffeinate.rawValue)
          Confirmation / Rollback: \(config.effectiveConfirmation.policy.rawValue), \(config.effectiveConfirmation.timeoutSeconds)s
          Soft Disconnect: \(config.softDisconnectBuiltInDisplay == true ? "Enabled (experimental)" : "Disabled")

        Suggested Next Step:
          \(suggestedNextStep(state: state, hasAlternativeDisplay: external != nil || managedVirtual != nil, policy: virtualDisplayPolicy, displayCount: displays.count))
        """
    }


    private func fileStatus(_ url: URL) -> String {
        FileManager.default.fileExists(atPath: url.path) ? "OK (\(url.path))" : "Missing (\(url.path))"
    }

    private func journalFileStatus(result: Result<RecoveryJournal?, Error>) -> String {
        switch result {
        case .success(.some): return "OK (\(CodexHeadlessPaths.recoveryJournalFile.path))"
        case .success(.none): return "Missing (\(CodexHeadlessPaths.recoveryJournalFile.path))"
        case .failure(let error as RecoveryJournalStoreError):
            if case .unsupportedSchema(let version) = error {
                return "Future schema v\(version), preserved (\(CodexHeadlessPaths.recoveryJournalFile.path))"
            }
            return "Damaged (\(error.localizedDescription))"
        case .failure(let error): return "Unavailable (\(error.localizedDescription))"
        }
    }

    private func overallStatus(
        external: DisplayInfo?,
        managedVirtual: DisplayInfo?,
        policy: VirtualDisplayPolicy
    ) -> String {
        if external != nil {
            return "Ready for Headless with external/dummy display"
        }
        if managedVirtual != nil {
            return "Ready for Headless with managed virtual display"
        }
        if policy != .off {
            return "Can create managed virtual display on `codex-headless on`"
        }
        return "Needs HDMI Dummy / external display or virtual-display-policy auto|always"
    }

    private func suggestedNextStep(
        state: RuntimeState,
        hasAlternativeDisplay: Bool,
        policy: VirtualDisplayPolicy,
        displayCount: Int
    ) -> String {
        guard hasAlternativeDisplay else {
            if displayCount == 0 {
                return "No displays are visible to this process. Run from the target GUI login session; with virtual-display-policy \(policy.rawValue), `codex-headless on` can still create a managed virtual display if allowed by macOS."
            }
            if policy == .off {
                return "Insert HDMI Dummy Plug or set `virtual-display-policy auto|always`, then run `codex-headless doctor` again."
            }
            return "Run `codex-headless on`; policy \(policy.rawValue) can create a managed virtual display when no external/dummy display is active."
        }

        switch state.mode {
        case .headless:
            return "Already Headless. Use `codex-headless off` to restore Normal Mode."
        case .confirmRequired:
            return "Run `codex-headless confirm` if the screen state is good, or `codex-headless off` to roll back."
        case .normal:
            return "Run `codex-headless on`, then `codex-headless confirm` if the screen state is good."
        case .fallback:
            return "Fallback is active. Check `codex-headless status` and logs, then confirm or restore."
        case .preparing:
            return "A transition is in progress. Check `codex-headless status`."
        case .restoring:
            return "Restore is in progress. Keep the managed virtual display alive until a physical display is available."
        case .error:
            return "Run `codex-headless off`, then inspect `codex-headless log --tail 100`."
        case .recoveryRequired:
            return "Runtime state requires recovery. Run `codex-headless off` before enabling Headless Mode again."
        }
    }
}
