import Foundation

public enum HeadlessMode: String, Codable {
    case normal = "Normal"
    case preparing = "Preparing"
    case confirmRequired = "Confirm Required"
    case headless = "Headless"
    case fallback = "Fallback"
    case error = "Error"
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
        scaleMode: "standard"
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

    public var effectiveHotkeys: HotkeysConfig {
        hotkeys ?? .default
    }

    public var effectiveConfirmDialog: ConfirmDialogConfig {
        confirmDialog ?? .default
    }

    public static let `default` = AppConfig(
        keepAwakeOnLaunch: false,
        startAtLogin: false,
        virtualDisplay: .default,
        rollback: .default,
        softDisconnectBuiltInDisplay: false,
        softDisconnectBlockedReason: nil,
        keepAwakeBackend: .caffeinate,
        hideTouchBarInHeadless: false,
        hotkeys: .default,
        confirmDialog: .default
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
        restoreCooldownUntil: nil
    )
}
