import Foundation

public struct StatusReportSnapshot {
    public var config: AppConfig
    public var configHealth: ConfigHealth
    public var state: RuntimeState
    public var displays: [DisplayInfo]
    public var builtInBrightness: Float?
    public var cleanNormalAssessment: CleanNormalAssessment?
    public var operationalEvidence: OperationalEvidence?
    public var journal: RecoveryJournal?
    public var journalError: String?

    public init(
        config: AppConfig,
        configHealth: ConfigHealth,
        state: RuntimeState,
        displays: [DisplayInfo],
        builtInBrightness: Float?,
        cleanNormalAssessment: CleanNormalAssessment? = nil,
        operationalEvidence: OperationalEvidence? = nil,
        journal: RecoveryJournal? = nil,
        journalError: String? = nil
    ) {
        self.config = config
        self.configHealth = configHealth
        self.state = state
        self.displays = displays
        self.builtInBrightness = builtInBrightness
        self.cleanNormalAssessment = cleanNormalAssessment
        self.operationalEvidence = operationalEvidence
        self.journal = journal
        self.journalError = journalError
    }
}

public struct StatusSnapshotProvider {
    private let configManager: ConfigManaging
    private let stateStore: RuntimeStateStoring
    private let displayManager: DisplayManaging
    private let builtInDisplayManager: BuiltInDisplayManaging

    public init(
        configManager: ConfigManaging,
        stateStore: RuntimeStateStoring,
        displayManager: DisplayManaging,
        builtInDisplayManager: BuiltInDisplayManaging
    ) {
        self.configManager = configManager
        self.stateStore = stateStore
        self.displayManager = displayManager
        self.builtInDisplayManager = builtInDisplayManager
    }

    public func snapshot() -> StatusReportSnapshot {
        StatusReportSnapshot(
            config: configManager.load(),
            configHealth: configManager.health(),
            state: stateStore.load(),
            displays: displayManager.displays(),
            builtInBrightness: builtInDisplayManager.currentBrightness(),
            cleanNormalAssessment: nil,
            journal: nil,
            journalError: nil
        )
    }
}

public struct StatusReportBuilder {
    private let snapshot: StatusReportSnapshot

    public init(snapshot: StatusReportSnapshot) {
        self.snapshot = snapshot
    }

    public func build() -> String {
        let config = snapshot.config
        let configHealth = snapshot.configHealth
        let state = snapshot.state
        let policy = VirtualDisplayPolicy.effectivePolicy(for: config.virtualDisplay)
        let confirmation = config.effectiveConfirmation
        let pidText = state.caffeinatePID.map(String.init) ?? "Not Running"
        let backend = state.keepAwakeBackend ?? config.keepAwakeBackend?.rawValue ?? KeepAwakeBackend.caffeinate.rawValue
        let deadline = state.rollbackDeadline.map { ISO8601DateFormatter().string(from: $0) } ?? "None"
        let rollback = state.rollbackConfirmed ? "Confirmed" : "Pending until \(deadline)"
        let activeResolution = state.activeResolutionOverride ?? config.virtualDisplay.resolution
        let requestedResolution = state.virtualDisplayRequestedResolution ?? activeResolution
        let refreshRate = state.virtualDisplayRefreshRate ?? config.virtualDisplay.refreshRate
        let scaleMode = state.virtualDisplayScaleMode ?? config.virtualDisplay.scaleMode
        let displays = snapshot.displays
        let main = displays.first { $0.isMain }
        let virtual = state.virtualDisplayID.flatMap { id in displays.first { $0.id == id } }
        let observedResolution = virtual.map { "\($0.width)x\($0.height)" } ?? "Not Active"
        let backingScale = virtual.map {
            backingScaleText(requested: requestedResolution, observedWidth: $0.width, observedHeight: $0.height)
        } ?? "Not Active"
        let mainText = main.map { display -> String in
            if display.id == state.virtualDisplayID { return "Managed Virtual" }
            return display.isBuiltIn ? "Built-in" : "External / Dummy"
        } ?? "Unknown"
        let brightness = snapshot.builtInBrightness.map { String(format: "%.2f", $0) } ?? "Unknown"
        let builtInHandling: String
        if state.builtInSoftDisconnected == true {
            builtInHandling = "Soft-disconnected\(state.builtInSoftDisconnectMethod.map { " via \($0)" } ?? "")"
        } else if state.builtInBrightnessDimmed == true {
            builtInHandling = "Dimmed\(state.builtInBrightnessMethod.map { " via \($0)" } ?? "")"
        } else if state.lastError?.contains("brightness control was unavailable") == true {
            builtInHandling = "Active (brightness control unavailable)"
        } else {
            builtInHandling = "Active / Not Dimmed"
        }
        let softDisconnect = state.builtInSoftDisconnectLastMessage.map { "\nSoft Disconnect: \($0)" } ?? ""
        let touchBar = state.touchBarLastMessage.map { "\nTouch Bar: \($0)" } ?? ""
        let lastError = state.lastError.map { "\nLast Error: \($0)" } ?? ""
        let lastWarning = state.lastWarning.map { "\nLast Warning: \($0)" } ?? ""
        let elapsed = RuntimePhaseFormatter.elapsedSeconds(state).map { "\($0)s" } ?? "Not Active"
        let phaseDeadline = RuntimePhaseFormatter.deadlineRemainingSeconds(state).map { "\($0)s" } ?? "Not Active"
        let cleanNormal = snapshot.cleanNormalAssessment
        let cleanNormalViolations = cleanNormal?.violations.joined(separator: " | ") ?? "Not assessed"
        let operational = state.mode == .normal
            ? OperationalSafetyPresentation.makeNormal(cleanNormal)
            : OperationalSafetyPresentation.make(
                state: state,
                availability: snapshot.operationalEvidence.map(OperationalEvidenceAvailability.fresh) ?? .unavailable(snapshot.journalError)
            )
        let evidence = snapshot.operationalEvidence

        return """
        CodexHeadless Status
        --------------------
        Mode: \(state.mode.rawValue)
        Diagnostic Logging: \(config.effectiveDiagnosticLoggingEnabled ? "Enabled" : "Disabled")
        Operational Safety: \(operational.title)
        Operational Evidence: \(evidence.map { "fresh (\(Int(Date().timeIntervalSince($0.capturedAt)))s, \($0.source.rawValue))" } ?? "Not available")
        Normal Readiness: \(operational.normalReadinessText)
        Clean Normal Violations: \(cleanNormalViolations)
        Recommended Action: \(operational.recommendedAction)
        Last Outcome: \(state.lastOutcome?.rawValue ?? "None")
        Phase: \(RuntimePhaseFormatter.phase(state).rawValue)
        Phase Message: \(RuntimePhaseFormatter.message(state))
        Phase Elapsed: \(elapsed)
        Phase Deadline: \(phaseDeadline)
        Cooldown Remaining: \(RuntimePhaseFormatter.cooldownRemainingSeconds(state))s
        Keep Awake: \(state.keepAwake ? "On" : "Off")
        Keep Awake Backend: \(backend)
        Assertion Holder PID: \(pidText)
        Keep Awake Observed Owner: \(cleanNormal?.keepAwakeObservation.status.rawValue ?? "notAssessed")
        Operational Keep Awake Owner: \(evidence?.keepAwake.status.rawValue ?? "notAssessed")

        Displays:
        \(statusLines(displays: displays, managedVirtualDisplayID: state.virtualDisplayID).joined(separator: "\n"))

        Virtual Display:
          Active: \(state.virtualDisplayCreated ? "Yes" : "No")
          Requested Resolution: \(state.virtualDisplayCreated ? "\(requestedResolution) @ \(refreshRate)Hz" : "Not Active")
          Requested Scale Mode: \(state.virtualDisplayCreated ? scaleMode : "Not Active")
          Observed Resolution: \(observedResolution)
          Backing Scale: \(backingScale)
          Display ID: \(state.virtualDisplayID.map(String.init) ?? "Not Active")
          Host PID: \(state.virtualDisplayPID.map(String.init) ?? "Not Running")
          Host Instance: \(state.virtualDisplayHost?.instanceID ?? "Not Active")
          Observed Owner: \(cleanNormal?.virtualDisplayObservation.status.rawValue ?? "notAssessed")
          Operational Owner: \(evidence?.virtualDisplay.status.rawValue ?? "notAssessed")
          Operational Expected/Observed ID: \(evidence?.display.expectedManagedDisplayID.map(String.init) ?? "none") / \(evidence?.display.observedManagedDisplayID.map(String.init) ?? "none")

        Recovery Journal:
          Active: \(snapshot.journal != nil ? "Yes" : "No")
          Schema: \(snapshot.journal.map { String($0.schemaVersion) } ?? "None")
          Stage: \(snapshot.journal?.stage.rawValue ?? "None")
          Error: \(snapshot.journalError ?? "None")

        Configured Virtual Display:
          Policy: \(policy.rawValue)
          Resolution: \(config.virtualDisplay.resolution)
          Refresh Rate: \(config.virtualDisplay.refreshRate)Hz
          Scale Mode: \(config.virtualDisplay.scaleMode)

        Display Handoff:
          Built-in ID: \(state.builtInDisplayID.map(String.init) ?? "Not Active")
          Built-in Was Main: \(state.builtInWasMain.map { $0 ? "Yes" : "No" } ?? "Unknown")
          Replacement Type: \(state.replacementDisplayType ?? "Not Active")
          Replacement ID: \(state.replacementDisplayID.map(String.init) ?? "Not Active")
          Replacement Ready: \(state.replacementDisplayReady == true ? "Yes" : "No")
          Replacement Promoted: \(state.replacementDisplayPromoted == true ? "Yes" : "No")

        Confirmation:
          Policy: \(confirmation.policy.rawValue)
          Required: \(state.confirmationRequired == true ? "Yes" : "No")
          Timeout: \(confirmation.timeoutSeconds)s
          Dialog: \(confirmation.dialogEnabled ? "On" : "Off")

        Main Display: \(mainText)
        Built-in Brightness: \(brightness)
        Built-in Handling: \(builtInHandling)
        Touch Bar: \(state.touchBarHidden == true ? "UI hidden\(state.touchBarHideMethod.map { " via \($0)" } ?? "")" : "Active / Not Hidden")
        Rollback Guard: \(rollback)
        Log: \(CodexHeadlessPaths.logFile.path)
        Config: \(CodexHeadlessPaths.configFile.path)\(softDisconnect)\(touchBar)\(lastError)
        Config Health: \(configHealth.isHealthy ? "Healthy" : "Degraded")\(lastWarning)
        """
    }

    private func backingScaleText(requested: Resolution, observedWidth: Int, observedHeight: Int) -> String {
        guard observedWidth > 0, observedHeight > 0 else { return "Unknown" }
        let widthScale = Double(requested.width) / Double(observedWidth)
        let heightScale = Double(requested.height) / Double(observedHeight)
        if abs(widthScale - heightScale) < 0.01 {
            return String(format: "%.2fx requested/observed", widthScale)
        }
        return String(format: "%.2fx width, %.2fx height requested/observed", widthScale, heightScale)
    }

    private func statusLines(displays: [DisplayInfo], managedVirtualDisplayID: UInt32?) -> [String] {
        guard !displays.isEmpty else { return ["  No displays detected."] }
        return displays.map { display in
            let type = display.id == managedVirtualDisplayID ? "Managed Virtual" : display.typeLabel
            return "  - ID: \(display.id) | \(type) | \(display.width)x\(display.height) | main=\(display.isMain ? "yes" : "no") | active=\(display.isActive ? "yes" : "no") | online=\(display.isOnline ? "yes" : "no")"
        }
    }
}
