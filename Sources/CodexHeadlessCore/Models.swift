import Foundation

public enum HeadlessMode: String, Codable {
    case normal = "Normal"
    case preparing = "Preparing"
    case confirmRequired = "Confirm Required"
    case headless = "Headless"
    case fallback = "Fallback"
    case restoring = "Restoring"
    case error = "Error"
}

public enum RuntimePhase: String, Codable {
    case idle
    case startingKeepAwake
    case checkingDisplays
    case usingExternalDisplay
    case creatingVirtualDisplay
    case waitingForVirtualDisplayEnumeration
    case acceptingReportedVirtualDisplayID
    case promotingVirtualDisplay
    case promotingExternalDisplay
    case disconnectingBuiltInDisplay
    case waitingForBuiltInDisplayDisconnect
    case hidingTouchBar
    case waitingForConfirmation
    case rollbackExpired
    case restoringBuiltInDisplay
    case waitingForPhysicalDisplay
    case promotingPhysicalDisplay
    case keepingExternalDisplayAsMain
    case restoringTouchBar
    case restoringBrightness
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
        case .usingExternalDisplay: "Using external display as main display..."
        case .creatingVirtualDisplay: "Creating virtual display..."
        case .waitingForVirtualDisplayEnumeration: "Waiting for macOS to detect the virtual display..."
        case .acceptingReportedVirtualDisplayID: "Using the reported virtual display ID..."
        case .promotingVirtualDisplay: "Setting virtual display as main display..."
        case .promotingExternalDisplay: "Setting external display as main display..."
        case .disconnectingBuiltInDisplay: "Disconnecting built-in display..."
        case .waitingForBuiltInDisplayDisconnect: "Checking built-in display state..."
        case .hidingTouchBar: "Hiding Touch Bar UI..."
        case .waitingForConfirmation: "Waiting for confirmation..."
        case .rollbackExpired: "Rollback deadline expired. Restoring Normal Mode..."
        case .restoringBuiltInDisplay: "Restoring built-in display..."
        case .waitingForPhysicalDisplay: "Waiting for a physical display to become available..."
        case .promotingPhysicalDisplay: "Setting physical display as main display..."
        case .keepingExternalDisplayAsMain: "Keeping external display as main display..."
        case .restoringTouchBar: "Restoring Touch Bar UI..."
        case .restoringBrightness: "Restoring display brightness..."
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
    public static let defaultResolution = Resolution(width: 2560, height: 1440)

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
            throw NSError(
                domain: "CodexHeadless.VirtualDisplayScaleMode",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid scale mode: use standard or hidpi."]
            )
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
            throw NSError(
                domain: "CodexHeadless.VirtualDisplayPolicy",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid virtual display policy: use auto, always, or off."]
            )
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
        scaleMode: "hidpi"
    )
}

public struct RollbackConfig: Codable {
    public var enabled: Bool
    public var timeoutSeconds: Int

    public static let `default` = RollbackConfig(enabled: true, timeoutSeconds: 30)
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

public struct TimingConfig: Codable {
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
    public var keepAwakeOnLaunch: Bool
    public var startAtLogin: Bool
    public var virtualDisplay: VirtualDisplayConfig
    public var rollback: RollbackConfig
    public var softDisconnectBuiltInDisplay: Bool?
    public var softDisconnectBlockedReason: String?
    public var keepAwakeBackend: KeepAwakeBackend?
    public var hideTouchBarInHeadless: Bool?
    public var hotkeys: HotkeysConfig?
    public var confirmDialog: ConfirmDialogConfig?
    public var timing: TimingConfig?

    public var effectiveHotkeys: HotkeysConfig {
        hotkeys ?? .default
    }

    public var effectiveConfirmDialog: ConfirmDialogConfig {
        confirmDialog ?? .default
    }

    public var effectiveTiming: TimingConfig {
        timing ?? .default
    }

    public static let `default` = AppConfig(
        keepAwakeOnLaunch: false,
        startAtLogin: false,
        virtualDisplay: .default,
        rollback: .default,
        softDisconnectBuiltInDisplay: true,
        softDisconnectBlockedReason: nil,
        keepAwakeBackend: .caffeinate,
        hideTouchBarInHeadless: true,
        hotkeys: .default,
        confirmDialog: .default,
        timing: .default
    )
}

public struct RuntimeState: Codable {
    public var mode: HeadlessMode
    public var keepAwake: Bool
    public var caffeinatePID: Int32?
    public var rollbackDeadline: Date?
    public var rollbackConfirmed: Bool
    public var lastError: String?
    public var originalBrightness: Float?
    public var activeResolutionOverride: Resolution?
    public var virtualDisplayCreated: Bool
    public var virtualDisplayPID: Int32?
    public var virtualDisplayID: UInt32?
    public var virtualDisplayRequestedResolution: Resolution?
    public var virtualDisplayRefreshRate: Int?
    public var virtualDisplayScaleMode: String?
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

    public static let `default` = RuntimeState(
        mode: .normal,
        keepAwake: false,
        caffeinatePID: nil,
        rollbackDeadline: nil,
        rollbackConfirmed: true,
        lastError: nil,
        originalBrightness: nil,
        activeResolutionOverride: nil,
        virtualDisplayCreated: false,
        virtualDisplayPID: nil,
        virtualDisplayID: nil,
        virtualDisplayRequestedResolution: nil,
        virtualDisplayRefreshRate: nil,
        virtualDisplayScaleMode: nil,
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
        lastProgressAt: nil
    )
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
