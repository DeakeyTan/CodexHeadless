import Foundation

public enum HeadlessMode: String, Codable {
    case normal = "Normal"
    case preparing = "Preparing"
    case confirmRequired = "Confirm Required"
    case headless = "Headless"
    case fallback = "Fallback"
    case restoring = "Restoring"
    case error = "Error"
    case recoveryRequired = "Recovery Required"
}

public enum OperationOutcome: String, Codable {
    case success
    case recoveredWithWarning
    case pausedForSafety
    case recoveryRequired
    case failed
}

public enum FailureSafetyOutcome: Equatable {
    case normalPreserved
    case normalRestored
    case pausedWithReplacement
    case recoveryRequired
    case unsafeFailure
}

public enum ManagedResourceCleanupResult: Equatable {
    case stopped
    case alreadyStopped
    case ownershipMismatch(reason: String)
    case failed(reason: String)

    public var completed: Bool {
        switch self {
        case .stopped, .alreadyStopped: true
        case .ownershipMismatch, .failed: false
        }
    }

    public var summary: String {
        switch self {
        case .stopped: "stopped"
        case .alreadyStopped: "already stopped"
        case .ownershipMismatch(let reason): "ownership mismatch: \(reason)"
        case .failed(let reason): "failed: \(reason)"
        }
    }
}

public enum CleanupStageResult: String, Codable, Equatable {
    case pending
    case completed
    case skipped
    case skippedNotRequired
    case blockedOwnership
    case failed
    case unknown
}

public struct RestoreCleanupProgress: Codable, Equatable {
    public var physicalTakeoverVerified: Bool
    public var virtualDisplayCleanup: CleanupStageResult
    public var keepAwakeCleanup: CleanupStageResult
    public var touchBarRestore: CleanupStageResult
    public var brightnessRestore: CleanupStageResult
    public var finalStatePersisted: Bool
    public var brightnessVerification: CleanupStageResult?
    public var virtualHostStop: CleanupStageResult?
    public var virtualDisplayDisappearance: CleanupStageResult?
    public var keepAwakeHolderStop: CleanupStageResult?
    public var keepAwakeAssertionDisappearance: CleanupStageResult?
    public var runtimeStatePersistence: CleanupStageResult?
    public var journalFinalization: CleanupStageResult?

    public init(
        physicalTakeoverVerified: Bool = false,
        virtualDisplayCleanup: CleanupStageResult = .pending,
        keepAwakeCleanup: CleanupStageResult = .pending,
        touchBarRestore: CleanupStageResult = .pending,
        brightnessRestore: CleanupStageResult = .pending,
        finalStatePersisted: Bool = false
    ) {
        self.physicalTakeoverVerified = physicalTakeoverVerified
        self.virtualDisplayCleanup = virtualDisplayCleanup
        self.keepAwakeCleanup = keepAwakeCleanup
        self.touchBarRestore = touchBarRestore
        self.brightnessRestore = brightnessRestore
        self.finalStatePersisted = finalStatePersisted
        brightnessVerification = nil
        virtualHostStop = nil
        virtualDisplayDisappearance = nil
        keepAwakeHolderStop = nil
        keepAwakeAssertionDisappearance = nil
        runtimeStatePersistence = nil
        journalFinalization = nil
    }
}

public enum RestoreResult: Equatable {
    case completed
    case alreadyNormal
    case pausedForSafety(reason: String)
    case recoveryRequired(reason: String)
    case cleanupIncomplete(progress: RestoreCleanupProgress, reason: String)
    case failed(reason: String)

    public var succeeded: Bool {
        switch self {
        case .completed, .alreadyNormal: true
        case .pausedForSafety, .recoveryRequired, .cleanupIncomplete, .failed: false
        }
    }

    public var message: String {
        switch self {
        case .completed: "Normal Mode restored."
        case .alreadyNormal: "Normal Mode is already restored."
        case .pausedForSafety(let reason): "Restore paused for safety: \(reason)"
        case .recoveryRequired(let reason): "Recovery is still required: \(reason)"
        case .cleanupIncomplete(_, let reason): "Restore cleanup is incomplete: \(reason)"
        case .failed(let reason): "Restore failed: \(reason)"
        }
    }
}

public enum FailedHandoffRecoveryResult: Equatable {
    case physicalDisplayRecovered(displayID: UInt32)
    case replacementMustRemainActive(reason: String)
}

public enum RuntimePhase: String, Codable {
    case idle
    case startingKeepAwake
    case checkingDisplays
    case preparingExternalDisplay
    case creatingVirtualDisplay
    case waitingForVirtualDisplayEnumeration
    case acceptingReportedVirtualDisplayID
    case validatingVirtualDisplay
    case replacementDisplayReady
    case committingDisplayHandoff
    case disconnectingBuiltInDisplay
    case waitingForBuiltInDisplayDisconnect
    case verifyingDisplayHandoff
    case hidingTouchBar
    case waitingForConfirmation
    case headlessActive
    case rollbackExpired
    case restoringBuiltInDisplay
    case waitingForPhysicalDisplay
    case promotingPhysicalDisplay
    case keepingExternalDisplayAsMain
    case restoringTouchBar
    case restoringBrightness
    case cleanupInProgress
    case stoppingVirtualDisplay
    case stoppingKeepAwake
    case coolingDown
    case restorePaused
    case error

    public var message: String {
        switch self {
        case .idle: "Ready."
        case .startingKeepAwake: "Starting Keep Awake..."
        case .checkingDisplays: "Checking displays..."
        case .preparingExternalDisplay: "Preparing external display..."
        case .creatingVirtualDisplay: "Creating virtual display..."
        case .waitingForVirtualDisplayEnumeration: "Waiting for macOS to detect the virtual display..."
        case .acceptingReportedVirtualDisplayID: "Using the reported virtual display ID..."
        case .validatingVirtualDisplay: "Validating virtual display..."
        case .replacementDisplayReady: "Replacement display is ready."
        case .committingDisplayHandoff: "Switching to replacement display..."
        case .disconnectingBuiltInDisplay: "Disconnecting built-in display..."
        case .waitingForBuiltInDisplayDisconnect: "Checking built-in display state..."
        case .verifyingDisplayHandoff: "Verifying display handoff..."
        case .hidingTouchBar: "Hiding Touch Bar UI..."
        case .waitingForConfirmation: "Waiting for confirmation..."
        case .headlessActive: "Headless Mode is active."
        case .rollbackExpired: "Rollback deadline expired. Restoring Normal Mode..."
        case .restoringBuiltInDisplay: "Restoring built-in display..."
        case .waitingForPhysicalDisplay: "Waiting for a physical display to become available..."
        case .promotingPhysicalDisplay: "Setting physical display as main display..."
        case .keepingExternalDisplayAsMain: "Keeping external display as main display..."
        case .restoringTouchBar: "Restoring Touch Bar UI..."
        case .restoringBrightness: "Restoring display brightness..."
        case .cleanupInProgress: "Cleaning managed resources..."
        case .stoppingVirtualDisplay: "Stopping virtual display..."
        case .stoppingKeepAwake: "Stopping Keep Awake..."
        case .coolingDown: "Waiting for display state to stabilize..."
        case .restorePaused: "Restore paused. Waiting for a physical display..."
        case .error: "An error occurred. Check the log or run restore."
        }
    }
}

public struct Resolution: Codable, Equatable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var description: String {
        "\(width)x\(height)"
    }
}

public enum ResolutionError: LocalizedError {
    case invalidFormat
    case invalidWidth
    case invalidHeight
    case mustBeEven

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid resolution: expected WIDTHxHEIGHT, for example 1920x1080."
        case .invalidWidth:
            return "Invalid resolution: width must be between 1024 and 3840."
        case .invalidHeight:
            return "Invalid resolution: height must be between 768 and 2160."
        case .mustBeEven:
            return "Invalid resolution: width and height must both be even numbers."
        }
    }
}

public enum ResolutionManager {
    public static let defaultResolution = Resolution(width: 1920, height: 1080)

    public static let presets: [Resolution] = [
        Resolution(width: 1280, height: 720),
        Resolution(width: 1600, height: 900),
        Resolution(width: 1920, height: 1080),
        Resolution(width: 2560, height: 1440),
        Resolution(width: 3008, height: 1692),
        Resolution(width: 3840, height: 2160)
    ]

    public static func parse(_ rawValue: String) throws -> Resolution {
        let parts = rawValue.lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]) else {
            throw ResolutionError.invalidFormat
        }

        let resolution = Resolution(width: width, height: height)
        try validate(resolution)
        return resolution
    }

    public static func validate(_ resolution: Resolution) throws {
        guard resolution.width >= 1024, resolution.width <= 3840 else {
            throw ResolutionError.invalidWidth
        }
        guard resolution.height >= 768, resolution.height <= 2160 else {
            throw ResolutionError.invalidHeight
        }
        guard resolution.width.isMultiple(of: 2), resolution.height.isMultiple(of: 2) else {
            throw ResolutionError.mustBeEven
        }
    }
}

public enum VirtualDisplayScaleMode: String, Codable {
    case standard
    case hidpi

    public static func parse(_ rawValue: String) throws -> VirtualDisplayScaleMode {
        let normalized = rawValue.lowercased()
        guard let mode = VirtualDisplayScaleMode(rawValue: normalized) else {
            throw CodexHeadlessError.invalidConfiguration(message: "Invalid scale mode: use standard or hidpi.")
        }
        return mode
    }
}

public enum VirtualDisplayPolicy: String, Codable {
    case auto
    case always
    case off

    public static func parse(_ rawValue: String) throws -> VirtualDisplayPolicy {
        let normalized = rawValue.lowercased()
        guard let policy = VirtualDisplayPolicy(rawValue: normalized) else {
            throw CodexHeadlessError.invalidConfiguration(message: "Invalid virtual display policy: use auto, always, or off.")
        }
        return policy
    }

    public static func effectivePolicy(for config: VirtualDisplayConfig) -> VirtualDisplayPolicy {
        if let policy = config.policy,
           let parsed = try? parse(policy) {
            return parsed
        }

        return config.enabled ? .auto : .off
    }
}

public struct VirtualDisplayConfig: Codable {
    public var enabled: Bool
    public var policy: String?
    public var resolution: Resolution
    public var refreshRate: Int
    public var scaleMode: String

    public static let `default` = VirtualDisplayConfig(
        enabled: true,
        policy: VirtualDisplayPolicy.auto.rawValue,
        resolution: ResolutionManager.defaultResolution,
        refreshRate: 60,
        scaleMode: "standard"
    )
}

struct LegacyRollbackConfig: Codable {
    public var enabled: Bool
    public var timeoutSeconds: Int

}

public enum KeepAwakeBackend: String, Codable {
    case caffeinate
    case native
}

public struct HotkeyShortcutConfig: Codable {
    public var key: String
    public var modifiers: [String]

    public var displayString: String {
        modifiers.map { modifier in
            switch modifier.lowercased() {
            case "control": return "⌃"
            case "option": return "⌥"
            case "command": return "⌘"
            case "shift": return "⇧"
            default: return modifier
            }
        }.joined() + key.uppercased()
    }
}

public struct HotkeysConfig: Codable {
    public var enabled: Bool
    public var enable: HotkeyShortcutConfig
    public var confirm: HotkeyShortcutConfig
    public var restore: HotkeyShortcutConfig

    public static let `default` = HotkeysConfig(
        enabled: true,
        enable: HotkeyShortcutConfig(key: "E", modifiers: ["control", "option", "command", "shift"]),
        confirm: HotkeyShortcutConfig(key: "C", modifiers: ["control", "option", "command", "shift"]),
        restore: HotkeyShortcutConfig(key: "R", modifiers: ["control", "option", "command", "shift"])
    )
}

public struct ConfirmDialogConfig: Codable {
    public var enabled: Bool
    public var timeoutSeconds: Int
    public var showHotkeyHints: Bool
    public var showCountdown: Bool

    public static let `default` = ConfirmDialogConfig(
        enabled: true,
        timeoutSeconds: 30,
        showHotkeyHints: true,
        showCountdown: true
    )
}

public enum ConfirmationPolicy: String, Codable, CaseIterable {
    case always
    case softwareVirtualDisplayOnly = "software-virtual-display-only"
    case never

    public static func parse(_ rawValue: String) throws -> ConfirmationPolicy {
        guard let policy = ConfirmationPolicy(rawValue: rawValue.lowercased()) else {
            throw CodexHeadlessError.invalidConfiguration(message: "Invalid confirmation policy: use always, software-virtual-display-only, or never.")
        }
        return policy
    }

    public func requiresConfirmation(usedManagedVirtualDisplay: Bool) -> Bool {
        switch self {
        case .always: return true
        case .softwareVirtualDisplayOnly: return usedManagedVirtualDisplay
        case .never: return false
        }
    }
}

public struct ConfirmationConfig: Codable {
    public var policy: ConfirmationPolicy
    public var timeoutSeconds: Int
    public var dialogEnabled: Bool
    public var showHotkeyHints: Bool?
    public var showCountdown: Bool?

    public init(
        policy: ConfirmationPolicy,
        timeoutSeconds: Int,
        dialogEnabled: Bool,
        showHotkeyHints: Bool? = true,
        showCountdown: Bool? = true
    ) {
        self.policy = policy
        self.timeoutSeconds = timeoutSeconds
        self.dialogEnabled = dialogEnabled
        self.showHotkeyHints = showHotkeyHints
        self.showCountdown = showCountdown
    }

    public static let `default` = ConfirmationConfig(
        policy: .softwareVirtualDisplayOnly,
        timeoutSeconds: 30,
        dialogEnabled: true,
        showHotkeyHints: true,
        showCountdown: true
    )
}

public enum SoftDisconnectFailureBehavior: String, Codable, CaseIterable {
    case restore
    case brightnessFallback = "brightness-fallback"

    public static func parse(_ rawValue: String) throws -> SoftDisconnectFailureBehavior {
        guard let behavior = SoftDisconnectFailureBehavior(rawValue: rawValue.lowercased()) else {
            throw CodexHeadlessError.invalidConfiguration(message: "Invalid soft-disconnect failure behavior: use restore or brightness-fallback.")
        }
        return behavior
    }
}

public struct DisplayHandoffConfig: Codable {
    public var onSoftDisconnectFailure: SoftDisconnectFailureBehavior

    public static let `default` = DisplayHandoffConfig(
        onSoftDisconnectFailure: .restore
    )
}

public struct TimingConfig: Codable {
    public static let supportedKeys: Set<String> = [
        "virtualDisplayEnumerationWaitSeconds",
        "virtualDisplayReportedIDExtraWaitSeconds",
        "softDisconnectDisappearWaitSeconds",
        "restoreBuiltInShortWaitSeconds",
        "restorePhysicalDisplayWaitSeconds",
        "restorePhysicalDisplayGraceSeconds",
        "restorePhysicalDisplayGracePollIntervalMilliseconds",
        "restoreCooldownSeconds",
        "restoreCooldownAfterPausedSeconds",
        "restorePostPromoteStabilizationMilliseconds"
    ]

    public var virtualDisplayEnumerationWaitSeconds: Int
    public var virtualDisplayReportedIDExtraWaitSeconds: Int
    public var softDisconnectDisappearWaitSeconds: Int
    public var restoreBuiltInShortWaitSeconds: Int
    public var restorePhysicalDisplayWaitSeconds: Int
    public var restorePhysicalDisplayGraceSeconds: Int?
    public var restorePhysicalDisplayGracePollIntervalMilliseconds: Int?
    public var restoreCooldownSeconds: Int
    public var restoreCooldownAfterPausedSeconds: Int
    public var restorePostPromoteStabilizationMilliseconds: Int?

    public static let `default` = TimingConfig(
        virtualDisplayEnumerationWaitSeconds: 5,
        virtualDisplayReportedIDExtraWaitSeconds: 2,
        softDisconnectDisappearWaitSeconds: 1,
        restoreBuiltInShortWaitSeconds: 3,
        restorePhysicalDisplayWaitSeconds: 5,
        restorePhysicalDisplayGraceSeconds: 5,
        restorePhysicalDisplayGracePollIntervalMilliseconds: 250,
        restoreCooldownSeconds: 5,
        restoreCooldownAfterPausedSeconds: 5,
        restorePostPromoteStabilizationMilliseconds: 500
    )

    public static let safeRestoreDefault = TimingConfig(
        virtualDisplayEnumerationWaitSeconds: 5,
        virtualDisplayReportedIDExtraWaitSeconds: 2,
        softDisconnectDisappearWaitSeconds: 1,
        restoreBuiltInShortWaitSeconds: 3,
        restorePhysicalDisplayWaitSeconds: 5,
        restorePhysicalDisplayGraceSeconds: 5,
        restorePhysicalDisplayGracePollIntervalMilliseconds: 250,
        restoreCooldownSeconds: 5,
        restoreCooldownAfterPausedSeconds: 5,
        restorePostPromoteStabilizationMilliseconds: 500
    )

    public var effectiveRestorePhysicalDisplayGraceSeconds: Int {
        restorePhysicalDisplayGraceSeconds ?? Self.default.restorePhysicalDisplayGraceSeconds ?? 3
    }

    public var effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds: Int {
        restorePhysicalDisplayGracePollIntervalMilliseconds ?? Self.default.restorePhysicalDisplayGracePollIntervalMilliseconds ?? 250
    }

    public var effectiveRestorePostPromoteStabilizationMilliseconds: Int {
        restorePostPromoteStabilizationMilliseconds ?? Self.default.restorePostPromoteStabilizationMilliseconds ?? 750
    }
}

public struct AppConfig: Codable {
    public var schemaVersion: Int?
    public var startAtLogin: Bool
    public var virtualDisplay: VirtualDisplayConfig
    public var softDisconnectBuiltInDisplay: Bool?
    public var softDisconnectBlockedReason: String?
    public var keepAwakeBackend: KeepAwakeBackend?
    public var hideTouchBarInHeadless: Bool?
    public var hotkeys: HotkeysConfig?
    public var confirmation: ConfirmationConfig?
    public var displayHandoff: DisplayHandoffConfig?
    public var timing: TimingConfig?
    public var diagnosticLoggingEnabled: Bool?

    public var effectiveHotkeys: HotkeysConfig {
        hotkeys ?? .default
    }

    public var effectiveConfirmDialog: ConfirmDialogConfig {
        let confirmation = effectiveConfirmation
        return ConfirmDialogConfig(
            enabled: confirmation.dialogEnabled,
            timeoutSeconds: confirmation.timeoutSeconds,
            showHotkeyHints: confirmation.showHotkeyHints ?? true,
            showCountdown: confirmation.showCountdown ?? true
        )
    }

    public var effectiveConfirmation: ConfirmationConfig {
        confirmation ?? .default
    }

    public var effectiveDisplayHandoff: DisplayHandoffConfig {
        displayHandoff ?? .default
    }

    public var effectiveTiming: TimingConfig {
        timing ?? .default
    }

    public var effectiveDiagnosticLoggingEnabled: Bool {
        diagnosticLoggingEnabled ?? false
    }

    public static let `default` = AppConfig(
        schemaVersion: 2,
        startAtLogin: false,
        virtualDisplay: .default,
        softDisconnectBuiltInDisplay: false,
        softDisconnectBlockedReason: nil,
        keepAwakeBackend: .caffeinate,
        hideTouchBarInHeadless: false,
        hotkeys: .default,
        confirmation: .default,
        displayHandoff: .default,
        timing: .default,
        diagnosticLoggingEnabled: false
    )
}

public enum ConfigurationProfile: String, CaseIterable {
    case safeDefault = "safe-default"
    case intel2018 = "2018-intel-macbook-pro"
    case remoteDevelopment = "remote-development"
    case experimentalMaximumHeadless = "experimental-maximum-headless"

    public var displayName: String {
        switch self {
        case .safeDefault: return "Safe Default"
        case .intel2018: return "2018 Intel MacBook Pro"
        case .remoteDevelopment: return "Remote Development"
        case .experimentalMaximumHeadless: return "Experimental Maximum Headless"
        }
    }

    public var summary: String {
        switch self {
        case .safeDefault:
            return "1920x1080 standard, virtual display auto, soft-disconnect off, Touch Bar hide off."
        case .intel2018:
            return "2560x1440 HiDPI, virtual display auto, experimental soft-disconnect and Touch Bar hide on."
        case .remoteDevelopment:
            return "2560x1440 HiDPI, virtual display auto, conservative physical display handling."
        case .experimentalMaximumHeadless:
            return "Always create a virtual display and enable experimental soft-disconnect and Touch Bar hide."
        }
    }
}

public struct ManagedProcessOwnershipRecord: Codable, Equatable {
    public var instanceID: String
    public var pid: Int32
    public var executableCanonicalPath: String
    public var executableFileIdentity: String?
    public var processStartTime: String?
    public var expectedCommandFragments: [String]
    public var ownerOperationID: String
    public var resourceKind: String
    public var createdAt: Date

    public init(
        instanceID: String,
        pid: Int32,
        executableCanonicalPath: String,
        executableFileIdentity: String? = nil,
        processStartTime: String? = nil,
        expectedCommandFragments: [String],
        ownerOperationID: String,
        resourceKind: String,
        createdAt: Date
    ) {
        self.instanceID = instanceID
        self.pid = pid
        self.executableCanonicalPath = executableCanonicalPath
        self.executableFileIdentity = executableFileIdentity
        self.processStartTime = processStartTime
        self.expectedCommandFragments = expectedCommandFragments
        self.ownerOperationID = ownerOperationID
        self.resourceKind = resourceKind
        self.createdAt = createdAt
    }
}

public enum ManagedResourceCommitStage: String, Codable, Equatable {
    case intent
    case started
    case observed
    case committed
    case cleanupPending
    case cleaned
}

public enum ManagedResourceObservationStatus: String, Codable, Equatable {
    case none
    case verifiedOwned
    case possibleOwned
    case unknown
}

public struct ManagedResourceObservation: Equatable {
    public var status: ManagedResourceObservationStatus
    public var summary: String
    public var pid: Int32?

    public init(status: ManagedResourceObservationStatus, summary: String, pid: Int32? = nil) {
        self.status = status
        self.summary = summary
        self.pid = pid
    }

    public static let none = ManagedResourceObservation(status: .none, summary: "none")
}

public enum CleanNormalClassification: String, Equatable {
    case clean
    case resourceDirty
    case recoveryRequired
    case temporarilyUnavailable
    case unknown
}

public struct CleanNormalAssessment: Equatable {
    public var runtimeViolations: [String]
    public var journalViolation: String?
    public var observedResourceViolations: [String]
    public var displayViolations: [String]
    public var keepAwakeObservation: ManagedResourceObservation
    public var virtualDisplayObservation: ManagedResourceObservation
    public var runtimeReadSucceeded: Bool
    public var journalReadSucceeded: Bool
    public var processSnapshotSucceeded: Bool
    public var processSnapshotError: String?
    public var managedDisplayViolation: Bool
    public var physicalDisplayTemporarilyUnavailable: Bool

    public init(
        runtimeViolations: [String],
        journalViolation: String?,
        observedResourceViolations: [String],
        displayViolations: [String],
        keepAwakeObservation: ManagedResourceObservation,
        virtualDisplayObservation: ManagedResourceObservation,
        runtimeReadSucceeded: Bool = true,
        journalReadSucceeded: Bool = true,
        processSnapshotSucceeded: Bool = true,
        processSnapshotError: String? = nil,
        managedDisplayViolation: Bool = false,
        physicalDisplayTemporarilyUnavailable: Bool = false
    ) {
        self.runtimeViolations = runtimeViolations
        self.journalViolation = journalViolation
        self.observedResourceViolations = observedResourceViolations
        self.displayViolations = displayViolations
        self.keepAwakeObservation = keepAwakeObservation
        self.virtualDisplayObservation = virtualDisplayObservation
        self.runtimeReadSucceeded = runtimeReadSucceeded
        self.journalReadSucceeded = journalReadSucceeded
        self.processSnapshotSucceeded = processSnapshotSucceeded
        self.processSnapshotError = processSnapshotError
        self.managedDisplayViolation = managedDisplayViolation
        self.physicalDisplayTemporarilyUnavailable = physicalDisplayTemporarilyUnavailable
    }

    public var violations: [String] {
        runtimeViolations + [journalViolation].compactMap { $0 } + observedResourceViolations + displayViolations
    }
    public var classification: CleanNormalClassification {
        if !runtimeReadSucceeded || !journalReadSucceeded || journalViolation != nil { return .recoveryRequired }
        if !processSnapshotSucceeded
            || keepAwakeObservation.status == .unknown
            || virtualDisplayObservation.status == .unknown { return .unknown }
        if !runtimeViolations.isEmpty
            || !observedResourceViolations.isEmpty
            || managedDisplayViolation { return .resourceDirty }
        if physicalDisplayTemporarilyUnavailable { return .temporarilyUnavailable }
        return .clean
    }
    public var isClean: Bool { classification == .clean }
    public var recommendedAction: String {
        switch classification {
        case .clean: return "System is ready for Enable."
        case .temporarilyUnavailable: return "Wake the physical display and try Enable again."
        case .resourceDirty: return "Run Restore and verify managed resources are removed before Enable."
        case .recoveryRequired: return "Run Restore or Doctor and preserve recovery evidence."
        case .unknown: return "Open Status or Doctor; CodexHeadless could not verify system safety."
        }
    }
}

public struct ManagedResourceJournalRecord: Codable, Equatable {
    public var instanceID: String
    public var resourceKind: String
    public var operationID: String
    public var stage: ManagedResourceCommitStage
    public var ownership: ManagedProcessOwnershipRecord?
    public var displayID: UInt32?

    public init(
        instanceID: String,
        resourceKind: String,
        operationID: String,
        stage: ManagedResourceCommitStage,
        ownership: ManagedProcessOwnershipRecord? = nil,
        displayID: UInt32? = nil
    ) {
        self.instanceID = instanceID
        self.resourceKind = resourceKind
        self.operationID = operationID
        self.stage = stage
        self.ownership = ownership
        self.displayID = displayID
    }
}

public struct VirtualDisplayHostRecord: Codable, Equatable {
    public var instanceID: String
    public var pid: Int32
    public var executablePath: String
    public var startedAt: Date
    public var ownership: ManagedProcessOwnershipRecord?

    public init(instanceID: String, pid: Int32, executablePath: String, startedAt: Date, ownership: ManagedProcessOwnershipRecord? = nil) {
        self.instanceID = instanceID
        self.pid = pid
        self.executablePath = executablePath
        self.startedAt = startedAt
        self.ownership = ownership
    }
}

public struct KeepAwakeHostRecord: Codable, Equatable {
    public var instanceID: String
    public var pid: Int32?
    public var backend: KeepAwakeBackend
    public var executablePath: String?
    public var startedAt: Date
    public var ownerProcessKind: String
    public var ownership: ManagedProcessOwnershipRecord?
    public var assertionKind: String?

    public init(
        instanceID: String,
        pid: Int32?,
        backend: KeepAwakeBackend,
        executablePath: String?,
        startedAt: Date,
        ownerProcessKind: String,
        ownership: ManagedProcessOwnershipRecord? = nil,
        assertionKind: String? = nil
    ) {
        self.instanceID = instanceID
        self.pid = pid
        self.backend = backend
        self.executablePath = executablePath
        self.startedAt = startedAt
        self.ownerProcessKind = ownerProcessKind
        self.ownership = ownership
        self.assertionKind = assertionKind
    }
}

public enum RecoveryJournalStage: String, Codable, Equatable {
    case enabling
    case keepAwakeStarted
    case virtualDisplayStarted
    case replacementReady
    case handoffCommitted
    case builtInSoftDisconnected
    case headless
    case restoringPhysicalDisplay
    case cleanupInProgress
    case finalStatePersisted
    case recoveryRequired
}

public struct RecoveryJournal: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var operationID: String
    public var createdAt: Date
    public var updatedAt: Date
    public var builtInDisplayID: UInt32?
    public var builtInWasMain: Bool?
    public var builtInSoftDisconnected: Bool
    public var softDisconnectMethod: String?
    public var replacementDisplayID: UInt32?
    public var replacementDisplayType: String?
    public var virtualDisplayHost: VirtualDisplayHostRecord?
    public var keepAwakeHost: KeepAwakeHostRecord?
    public var keepAwakeResource: ManagedResourceJournalRecord?
    public var virtualDisplayResource: ManagedResourceJournalRecord?
    public var touchBarHidden: Bool?
    public var stage: RecoveryJournalStage
    public var cleanupProgress: RestoreCleanupProgress
    public var checksum: String?

    public init(operationID: String, createdAt: Date) {
        schemaVersion = Self.currentSchemaVersion
        self.operationID = operationID
        self.createdAt = createdAt
        updatedAt = createdAt
        builtInDisplayID = nil
        builtInWasMain = nil
        builtInSoftDisconnected = false
        softDisconnectMethod = nil
        replacementDisplayID = nil
        replacementDisplayType = nil
        virtualDisplayHost = nil
        keepAwakeHost = nil
        keepAwakeResource = nil
        virtualDisplayResource = nil
        touchBarHidden = nil
        stage = .enabling
        cleanupProgress = RestoreCleanupProgress()
        checksum = nil
    }
}

public struct RuntimeState: Codable {
    public var mode: HeadlessMode
    public var keepAwake: Bool
    public var caffeinatePID: Int32?
    public var keepAwakeHost: KeepAwakeHostRecord?
    public var rollbackDeadline: Date?
    public var rollbackConfirmed: Bool
    public var lastError: String?
    public var lastWarning: String?
    public var lastOutcome: OperationOutcome?
    public var originalBrightness: Float?
    public var activeResolutionOverride: Resolution?
    public var virtualDisplayCreated: Bool
    public var virtualDisplayPID: Int32?
    public var virtualDisplayID: UInt32?
    public var virtualDisplayRequestedResolution: Resolution?
    public var virtualDisplayRefreshRate: Int?
    public var virtualDisplayScaleMode: String?
    public var virtualDisplayHost: VirtualDisplayHostRecord?
    public var builtInBrightnessDimmed: Bool?
    public var builtInBrightnessMethod: String?
    public var externalDisplayPromoted: Bool?
    public var keepAwakeBackend: String?
    public var builtInSoftDisconnected: Bool?
    public var builtInSoftDisconnectMethod: String?
    public var softDisconnectedDisplayID: UInt32?
    public var builtInSoftDisconnectLastMessage: String?
    public var touchBarHidden: Bool?
    public var touchBarHideMethod: String?
    public var touchBarLastMessage: String?
    public var restoreCooldownUntil: Date?
    public var phase: RuntimePhase?
    public var phaseMessage: String?
    public var phaseStartedAt: Date?
    public var phaseDeadlineAt: Date?
    public var lastProgressAt: Date?
    public var builtInDisplayID: UInt32?
    public var builtInWasMain: Bool?
    public var replacementDisplayID: UInt32?
    public var replacementDisplayType: String?
    public var replacementDisplayReady: Bool?
    public var replacementDisplayPromoted: Bool?
    public var confirmationRequired: Bool?
    public var enableCancellationRequested: Bool?

    public static let `default` = RuntimeState(
        mode: .normal,
        keepAwake: false,
        caffeinatePID: nil,
        keepAwakeHost: nil,
        rollbackDeadline: nil,
        rollbackConfirmed: true,
        lastError: nil,
        lastWarning: nil,
        lastOutcome: nil,
        originalBrightness: nil,
        activeResolutionOverride: nil,
        virtualDisplayCreated: false,
        virtualDisplayPID: nil,
        virtualDisplayID: nil,
        virtualDisplayRequestedResolution: nil,
        virtualDisplayRefreshRate: nil,
        virtualDisplayScaleMode: nil,
        virtualDisplayHost: nil,
        builtInBrightnessDimmed: false,
        builtInBrightnessMethod: nil,
        externalDisplayPromoted: false,
        keepAwakeBackend: nil,
        builtInSoftDisconnected: false,
        builtInSoftDisconnectMethod: nil,
        softDisconnectedDisplayID: nil,
        builtInSoftDisconnectLastMessage: nil,
        touchBarHidden: false,
        touchBarHideMethod: nil,
        touchBarLastMessage: nil,
        restoreCooldownUntil: nil,
        phase: .idle,
        phaseMessage: RuntimePhase.idle.message,
        phaseStartedAt: nil,
        phaseDeadlineAt: nil,
        lastProgressAt: nil,
        builtInDisplayID: nil,
        builtInWasMain: nil,
        replacementDisplayID: nil,
        replacementDisplayType: nil,
        replacementDisplayReady: false,
        replacementDisplayPromoted: false,
        confirmationRequired: false,
        enableCancellationRequested: false
    )
}

public extension RuntimeState {
    var failureSafetyOutcome: FailureSafetyOutcome {
        if mode == .normal { return .normalRestored }
        if mode == .restoring, phase == .restorePaused { return .pausedWithReplacement }
        if mode == .recoveryRequired { return .recoveryRequired }
        return .unsafeFailure
    }

    static func recoveryRequired(message: String, now: Date = Date()) -> RuntimeState {
        var state = RuntimeState.default
        state.mode = .recoveryRequired
        state.phase = .error
        state.phaseMessage = "Runtime state is damaged. Run Safe Restore."
        state.phaseStartedAt = now
        state.lastProgressAt = now
        state.lastError = message
        state.lastOutcome = .recoveryRequired
        return state
    }
}

public enum RuntimePhaseFormatter {
    public static func phase(_ state: RuntimeState) -> RuntimePhase {
        state.phase ?? .idle
    }

    public static func message(_ state: RuntimeState) -> String {
        state.phaseMessage ?? phase(state).message
    }

    public static func elapsedSeconds(_ state: RuntimeState, now: Date = Date()) -> Int? {
        guard let startedAt = state.phaseStartedAt else {
            return nil
        }
        return max(0, Int(now.timeIntervalSince(startedAt).rounded(.down)))
    }

    public static func deadlineRemainingSeconds(_ state: RuntimeState, now: Date = Date()) -> Int? {
        guard let deadline = state.phaseDeadlineAt else {
            return nil
        }
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    public static func cooldownRemainingSeconds(_ state: RuntimeState, now: Date = Date()) -> Int {
        guard let cooldownUntil = state.restoreCooldownUntil,
              cooldownUntil > now else {
            return 0
        }
        return max(0, Int(ceil(cooldownUntil.timeIntervalSince(now))))
    }
}
