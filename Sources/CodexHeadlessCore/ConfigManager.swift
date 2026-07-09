import Foundation

public final class ConfigManager {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger: CHLogger

    public init(logger: CHLogger = CHLogger()) {
        self.logger = logger
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> AppConfig {
        do {
            try CodexHeadlessPaths.ensureDirectories()
            guard FileManager.default.fileExists(atPath: CodexHeadlessPaths.configFile.path) else {
                try save(.default)
                return .default
            }

            let data = try Data(contentsOf: CodexHeadlessPaths.configFile)
            return try decoder.decode(AppConfig.self, from: data)
        } catch {
            logger.error("Failed to load config: \(error.localizedDescription). Using defaults.")
            return .default
        }
    }

    public func save(_ config: AppConfig) throws {
        try CodexHeadlessPaths.ensureDirectories()
        let data = try encoder.encode(config)
        try data.write(to: CodexHeadlessPaths.configFile, options: .atomic)
    }

    public func setResolution(_ resolution: Resolution) throws {
        try ResolutionManager.validate(resolution)
        var config = load()
        config.virtualDisplay.resolution = resolution
        try save(config)
        logger.info("Configured virtual display resolution: \(resolution)")
    }

    public func setVirtualDisplayScaleMode(_ rawValue: String) throws {
        let scaleMode = try VirtualDisplayScaleMode.parse(rawValue)
        var config = load()
        config.virtualDisplay.scaleMode = scaleMode.rawValue
        try save(config)
        logger.info("Configured virtual display scale mode: \(scaleMode.rawValue)")
    }

    public func setVirtualDisplayPolicy(_ rawValue: String) throws {
        let policy = try VirtualDisplayPolicy.parse(rawValue)
        var config = load()
        config.virtualDisplay.policy = policy.rawValue
        config.virtualDisplay.enabled = policy != .off
        try save(config)
        logger.info("Configured software virtual display policy: \(policy.rawValue)")
    }

    public func setSoftDisconnectBuiltInDisplay(_ enabled: Bool) throws {
        var config = load()
        config.softDisconnectBuiltInDisplay = enabled
        if enabled {
            config.softDisconnectBlockedReason = nil
        }
        try save(config)
        logger.info("Configured experimental built-in display soft-disconnect: \(enabled ? "enabled" : "disabled")")
    }

    public func blockSoftDisconnect(reason: String) throws {
        var config = load()
        config.softDisconnectBuiltInDisplay = false
        config.softDisconnectBlockedReason = reason
        try save(config)
        logger.warn("Blocked experimental built-in display soft-disconnect: \(reason)")
    }

    public func clearSoftDisconnectBlock() throws {
        var config = load()
        config.softDisconnectBlockedReason = nil
        try save(config)
        logger.info("Cleared experimental built-in display soft-disconnect block.")
    }

    public func setKeepAwakeBackend(_ backend: KeepAwakeBackend) throws {
        var config = load()
        config.keepAwakeBackend = backend
        try save(config)
        logger.info("Configured Keep Awake backend: \(backend.rawValue)")
    }

    public func setHideTouchBarInHeadless(_ enabled: Bool) throws {
        var config = load()
        config.hideTouchBarInHeadless = enabled
        try save(config)
        logger.info("Configured experimental Touch Bar hide in Headless Mode: \(enabled ? "enabled" : "disabled")")
    }

    public func setHotkeysEnabled(_ enabled: Bool) throws {
        var config = load()
        var hotkeys = config.effectiveHotkeys
        hotkeys.enabled = enabled
        config.hotkeys = hotkeys
        try save(config)
        logger.info("Configured global hotkeys: \(enabled ? "enabled" : "disabled")")
    }

    public func setConfirmDialogEnabled(_ enabled: Bool) throws {
        var config = load()
        var confirmDialog = config.effectiveConfirmDialog
        confirmDialog.enabled = enabled
        config.confirmDialog = confirmDialog
        try save(config)
        logger.info("Configured Confirm/Rollback dialog: \(enabled ? "enabled" : "disabled")")
    }

    public func setTimingValue(key: String, seconds: Int) throws {
        guard seconds >= 0, seconds <= 120 else {
            throw NSError(domain: "CodexHeadless.Timing", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid timing value: use a value from 0 to 120 seconds."
            ])
        }

        var config = load()
        var timing = config.effectiveTiming
        switch key {
        case "virtualDisplayEnumerationWaitSeconds":
            timing.virtualDisplayEnumerationWaitSeconds = seconds
        case "virtualDisplayReportedIDExtraWaitSeconds":
            timing.virtualDisplayReportedIDExtraWaitSeconds = seconds
        case "softDisconnectDisappearWaitSeconds":
            timing.softDisconnectDisappearWaitSeconds = seconds
        case "restoreBuiltInShortWaitSeconds":
            timing.restoreBuiltInShortWaitSeconds = seconds
        case "restorePhysicalDisplayWaitSeconds":
            timing.restorePhysicalDisplayWaitSeconds = seconds
        case "restoreCooldownSeconds":
            timing.restoreCooldownSeconds = seconds
        case "restoreCooldownAfterPausedSeconds":
            timing.restoreCooldownAfterPausedSeconds = seconds
        default:
            throw NSError(domain: "CodexHeadless.Timing", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported timing key: \(key)"
            ])
        }

        config.timing = timing
        try save(config)
        logger.info("Configured timing.\(key): \(seconds)s")
    }
}
