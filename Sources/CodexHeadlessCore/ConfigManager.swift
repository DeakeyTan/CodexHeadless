import Darwin
import Foundation

public struct ConfigHealth: Codable {
    public var isHealthy: Bool
    public var message: String?
    public var damagedBackupPath: String?
    public var damagedContentHash: String?

    public init(isHealthy: Bool, message: String?, damagedBackupPath: String?, damagedContentHash: String? = nil) {
        self.isHealthy = isHealthy
        self.message = message
        self.damagedBackupPath = damagedBackupPath
        self.damagedContentHash = damagedContentHash
    }

    public static let healthy = ConfigHealth(isHealthy: true, message: nil, damagedBackupPath: nil)
}

public enum ConfigManagerError: LocalizedError {
    case unsupportedFutureSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFutureSchema(let version):
            return "Config schema v\(version) is newer than this CodexHeadless build supports. The original file was not modified."
        }
    }
}

private struct ConfigSchemaProbe: Decodable {
    var schemaVersion: Int?
}

private struct LegacyAppConfig: Decodable {
    var startAtLogin: Bool?
    var virtualDisplay: VirtualDisplayConfig?
    var rollback: LegacyRollbackConfig?
    var softDisconnectBuiltInDisplay: Bool?
    var softDisconnectBlockedReason: String?
    var keepAwakeBackend: KeepAwakeBackend?
    var hideTouchBarInHeadless: Bool?
    var hotkeys: HotkeysConfig?
    var confirmDialog: ConfirmDialogConfig?
    var confirmation: ConfirmationConfig?
    var displayHandoff: DisplayHandoffConfig?
    var timing: TimingConfig?
}

public final class ConfigManager {
    private static let processLock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger: CHLogger
    private let configFile: URL
    private let lockFile: URL
    private let healthFile: URL
    private let lockTimeoutSeconds: TimeInterval
    private let clock: WorkflowClock
    private let mutationGuard: ConfigurationMutationGuard?

    public init(
        logger: CHLogger = CHLogger(),
        configFile: URL = CodexHeadlessPaths.configFile,
        lockFile: URL = CodexHeadlessPaths.configLockFile,
        healthFile: URL = CodexHeadlessPaths.configHealthFile,
        lockTimeoutSeconds: TimeInterval = 2,
        clock: WorkflowClock = SystemWorkflowClock(),
        enforceMutationSafety: Bool? = nil
    ) {
        self.logger = logger
        self.configFile = configFile
        self.lockFile = lockFile
        self.healthFile = healthFile
        self.lockTimeoutSeconds = lockTimeoutSeconds
        self.clock = clock
        let isProductionPath = configFile.standardizedFileURL == CodexHeadlessPaths.configFile.standardizedFileURL
        mutationGuard = (enforceMutationSafety ?? isProductionPath) ? ConfigurationMutationGuard() : nil
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> AppConfig {
        do {
            return try withLock { try loadUnlocked() }
        } catch {
            logger.error("Failed to load config: \(error.localizedDescription). Safe defaults loaded; Enable is blocked until the config is repaired or reset.")
            return .default
        }
    }

    public func read() throws -> AppConfig {
        try withLock { try loadUnlocked() }
    }

    public func save(_ config: AppConfig) throws {
        let lease = try mutationGuard?.acquire()
        defer { lease?.release() }
        try withLock {
            var normalized = config
            normalized.schemaVersion = 2
            try saveUnlocked(normalized)
            try clearHealthUnlocked()
        }
    }

    public func health() -> ConfigHealth {
        (try? withLock { try healthUnlocked() }) ?? ConfigHealth(
            isHealthy: false,
            message: "Unable to read config health.",
            damagedBackupPath: nil
        )
    }

    public func setResolution(_ resolution: Resolution) throws {
        try ResolutionManager.validate(resolution)
        try mutate { $0.virtualDisplay.resolution = resolution }
        logger.info("Configured virtual display resolution: \(resolution)")
    }

    public func setVirtualDisplayScaleMode(_ rawValue: String) throws {
        let scaleMode = try VirtualDisplayScaleMode.parse(rawValue)
        try mutate { $0.virtualDisplay.scaleMode = scaleMode.rawValue }
        logger.info("Configured virtual display scale mode: \(scaleMode.rawValue)")
    }

    public func setVirtualDisplayPolicy(_ rawValue: String) throws {
        let policy = try VirtualDisplayPolicy.parse(rawValue)
        try mutate {
            $0.virtualDisplay.policy = policy.rawValue
            $0.virtualDisplay.enabled = policy != .off
        }
        logger.info("Configured software virtual display policy: \(policy.rawValue)")
    }

    public func setSoftDisconnectBuiltInDisplay(_ enabled: Bool) throws {
        try mutate {
            $0.softDisconnectBuiltInDisplay = enabled
            if enabled { $0.softDisconnectBlockedReason = nil }
        }
        logger.info("Configured experimental built-in display soft-disconnect: \(enabled ? "enabled" : "disabled")")
    }

    public func blockSoftDisconnect(reason: String) throws {
        try mutateWithoutSafetyGuard {
            $0.softDisconnectBuiltInDisplay = false
            $0.softDisconnectBlockedReason = reason
        }
        logger.warn("Blocked experimental built-in display soft-disconnect: \(reason)")
    }

    public func clearSoftDisconnectBlock() throws {
        try mutate { $0.softDisconnectBlockedReason = nil }
        logger.info("Cleared experimental built-in display soft-disconnect block.")
    }

    public func setKeepAwakeBackend(_ backend: KeepAwakeBackend) throws {
        let effective: KeepAwakeBackend = .caffeinate
        try mutate { $0.keepAwakeBackend = effective }
        if backend == .native {
            logger.warn("Native Keep Awake is unavailable for Headless Mode; configured managed caffeinate instead.")
        } else {
            logger.info("Configured Keep Awake backend: \(effective.rawValue)")
        }
    }

    public func setHideTouchBarInHeadless(_ enabled: Bool) throws {
        try mutate { $0.hideTouchBarInHeadless = enabled }
        logger.info("Configured experimental Touch Bar hide in Headless Mode: \(enabled ? "enabled" : "disabled")")
    }

    public func setHotkeysEnabled(_ enabled: Bool) throws {
        try mutate {
            var hotkeys = $0.effectiveHotkeys
            hotkeys.enabled = enabled
            $0.hotkeys = hotkeys
        }
        logger.info("Configured global hotkeys: \(enabled ? "enabled" : "disabled")")
    }

    public func setConfirmDialogEnabled(_ enabled: Bool) throws {
        try mutate {
            var confirmation = $0.effectiveConfirmation
            confirmation.dialogEnabled = enabled
            $0.confirmation = confirmation
        }
        logger.info("Configured Confirm/Rollback dialog: \(enabled ? "enabled" : "disabled")")
    }

    public func setConfirmationPolicy(_ rawValue: String) throws {
        let policy = try ConfirmationPolicy.parse(rawValue)
        try mutate {
            var confirmation = $0.effectiveConfirmation
            confirmation.policy = policy
            $0.confirmation = confirmation
        }
        logger.info("Configured confirmation policy: \(policy.rawValue)")
    }

    public func setConfirmationTimeoutSeconds(_ timeoutSeconds: Int) throws {
        guard timeoutSeconds >= 5, timeoutSeconds <= 300 else {
            throw CodexHeadlessError.invalidConfiguration(message: "Invalid confirmation timeout: use 5 to 300 seconds.")
        }
        try mutate {
            var confirmation = $0.effectiveConfirmation
            confirmation.timeoutSeconds = timeoutSeconds
            $0.confirmation = confirmation
        }
        logger.info("Configured confirmation timeout: \(timeoutSeconds)s")
    }

    public func setSoftDisconnectFailureBehavior(_ rawValue: String) throws {
        let behavior = try SoftDisconnectFailureBehavior.parse(rawValue)
        try mutate {
            var displayHandoff = $0.effectiveDisplayHandoff
            displayHandoff.onSoftDisconnectFailure = behavior
            $0.displayHandoff = displayHandoff
        }
        logger.info("Configured soft-disconnect failure behavior: \(behavior.rawValue)")
    }

    public func setTimingValue(key: String, value: Int) throws {
        let isMilliseconds = key.hasSuffix("Milliseconds")
        let maxValue = isMilliseconds ? 10_000 : 120
        guard value >= 0, value <= maxValue else {
            throw CodexHeadlessError.invalidConfiguration(message: "Invalid timing value: use a value from 0 to \(maxValue)\(isMilliseconds ? " milliseconds" : " seconds").")
        }

        try mutate { config in
            var timing = config.effectiveTiming
            switch key {
        case "virtualDisplayEnumerationWaitSeconds":
            timing.virtualDisplayEnumerationWaitSeconds = value
        case "virtualDisplayReportedIDExtraWaitSeconds":
            timing.virtualDisplayReportedIDExtraWaitSeconds = value
        case "softDisconnectDisappearWaitSeconds":
            timing.softDisconnectDisappearWaitSeconds = value
        case "restoreBuiltInShortWaitSeconds":
            timing.restoreBuiltInShortWaitSeconds = value
        case "restorePhysicalDisplayWaitSeconds":
            timing.restorePhysicalDisplayWaitSeconds = value
        case "restorePhysicalDisplayGraceSeconds":
            timing.restorePhysicalDisplayGraceSeconds = value
        case "restorePhysicalDisplayGracePollIntervalMilliseconds":
            timing.restorePhysicalDisplayGracePollIntervalMilliseconds = value
        case "restoreCooldownSeconds":
            timing.restoreCooldownSeconds = value
        case "restoreCooldownAfterPausedSeconds":
            timing.restoreCooldownAfterPausedSeconds = value
        case "restorePostPromoteStabilizationMilliseconds":
            timing.restorePostPromoteStabilizationMilliseconds = value
            default:
                throw CodexHeadlessError.invalidConfiguration(message: "Unsupported timing key: \(key)")
            }
            config.timing = timing
        }
        logger.info("Configured timing.\(key): \(value)\(isMilliseconds ? "ms" : "s")")
    }

    public func resetTimingToDefault() throws {
        try mutate { $0.timing = .default }
        logger.info("Reset timing configuration to defaults.")
    }

    public func resetConfigToDefault() throws {
        try save(.default)
        logger.info("Reset configuration to defaults.")
    }

    public func setDiagnosticLoggingEnabled(_ enabled: Bool) throws {
        try mutate { $0.diagnosticLoggingEnabled = enabled }
    }

    public func applyProfile(_ profile: ConfigurationProfile) throws {
        try mutate { config in
            switch profile {
            case .safeDefault:
                let startAtLogin = config.startAtLogin
                let hotkeys = config.hotkeys
                let diagnosticLoggingEnabled = config.diagnosticLoggingEnabled
                config = .default
                config.startAtLogin = startAtLogin
                config.hotkeys = hotkeys
                config.diagnosticLoggingEnabled = diagnosticLoggingEnabled
            case .intel2018:
                config.virtualDisplay.enabled = true
                config.virtualDisplay.policy = VirtualDisplayPolicy.auto.rawValue
                config.virtualDisplay.resolution = Resolution(width: 2560, height: 1440)
                config.virtualDisplay.scaleMode = VirtualDisplayScaleMode.hidpi.rawValue
                config.softDisconnectBuiltInDisplay = true
                config.softDisconnectBlockedReason = nil
                config.hideTouchBarInHeadless = true
                config.keepAwakeBackend = .caffeinate
            case .remoteDevelopment:
                config.virtualDisplay.enabled = true
                config.virtualDisplay.policy = VirtualDisplayPolicy.auto.rawValue
                config.virtualDisplay.resolution = Resolution(width: 2560, height: 1440)
                config.virtualDisplay.scaleMode = VirtualDisplayScaleMode.hidpi.rawValue
                config.softDisconnectBuiltInDisplay = false
                config.hideTouchBarInHeadless = false
                config.keepAwakeBackend = .caffeinate
            case .experimentalMaximumHeadless:
                config.virtualDisplay.enabled = true
                config.virtualDisplay.policy = VirtualDisplayPolicy.always.rawValue
                config.virtualDisplay.resolution = Resolution(width: 2560, height: 1440)
                config.virtualDisplay.scaleMode = VirtualDisplayScaleMode.hidpi.rawValue
                config.softDisconnectBuiltInDisplay = true
                config.softDisconnectBlockedReason = nil
                config.hideTouchBarInHeadless = true
                config.keepAwakeBackend = .caffeinate
                var confirmation = config.effectiveConfirmation
                confirmation.policy = .always
                config.confirmation = confirmation
            }
        }
        logger.info("Applied configuration profile: \(profile.displayName)")
    }

    private func mutate(_ mutation: (inout AppConfig) throws -> Void) throws {
        let lease = try mutationGuard?.acquire()
        defer { lease?.release() }
        try mutateWithoutSafetyGuard(mutation)
    }

    private func mutateWithoutSafetyGuard(_ mutation: (inout AppConfig) throws -> Void) throws {
        try withLock {
            var config = try loadUnlocked()
            try mutation(&config)
            config.schemaVersion = 2
            try saveUnlocked(config)
            try clearHealthUnlocked()
        }
    }

    private func loadUnlocked() throws -> AppConfig {
        try ensureDirectory()
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            try saveUnlocked(.default)
            try clearHealthUnlocked()
            return .default
        }

        do {
            let data = try Data(contentsOf: configFile)
            let schema = try decoder.decode(ConfigSchemaProbe.self, from: data).schemaVersion
            var config: AppConfig
            if let schema, schema > 2 {
                throw ConfigManagerError.unsupportedFutureSchema(schema)
            } else if schema == 2 {
                config = try decoder.decode(AppConfig.self, from: data)
            } else {
                config = try migrateUnlocked(originalData: data)
            }
            if config.keepAwakeBackend == .native {
                config.keepAwakeBackend = .caffeinate
                try saveUnlocked(config)
                logger.warn("Migrated Native Keep Awake to managed caffeinate for cross-process recovery safety.")
            }
            try clearHealthUnlocked()
            return config
        } catch {
            let backup = try backupDamagedConfigUnlocked()
            let health = ConfigHealth(
                isHealthy: false,
                message: "Config decode failed: \(error.localizedDescription)",
                damagedBackupPath: backup.path,
                damagedContentHash: backup.deletingPathExtension().lastPathComponent.split(separator: ".").last.map(String.init)
            )
            try encoder.encode(health).write(to: healthFile, options: .atomic)
            throw error
        }
    }

    private func migrateUnlocked(originalData: Data) throws -> AppConfig {
        let backup = configFile.deletingLastPathComponent().appendingPathComponent("config.v1.backup.json")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try originalData.write(to: backup, options: .atomic)
        }
        let legacy = try decoder.decode(LegacyAppConfig.self, from: originalData)
        var config = AppConfig.default
        config.startAtLogin = legacy.startAtLogin ?? config.startAtLogin
        config.virtualDisplay = legacy.virtualDisplay ?? config.virtualDisplay
        config.softDisconnectBuiltInDisplay = legacy.softDisconnectBuiltInDisplay ?? config.softDisconnectBuiltInDisplay
        config.softDisconnectBlockedReason = legacy.softDisconnectBlockedReason
        config.keepAwakeBackend = legacy.keepAwakeBackend ?? config.keepAwakeBackend
        config.hideTouchBarInHeadless = legacy.hideTouchBarInHeadless ?? config.hideTouchBarInHeadless
        config.hotkeys = legacy.hotkeys ?? config.hotkeys
        config.displayHandoff = legacy.displayHandoff ?? config.displayHandoff
        config.timing = legacy.timing ?? config.timing

        if let confirmation = legacy.confirmation {
            config.confirmation = confirmation
        } else if let dialog = legacy.confirmDialog {
            config.confirmation = ConfirmationConfig(
                policy: .softwareVirtualDisplayOnly,
                timeoutSeconds: dialog.timeoutSeconds,
                dialogEnabled: dialog.enabled,
                showHotkeyHints: dialog.showHotkeyHints,
                showCountdown: dialog.showCountdown
            )
        } else if let rollback = legacy.rollback {
            var confirmation = ConfirmationConfig.default
            confirmation.policy = rollback.enabled ? .softwareVirtualDisplayOnly : .never
            confirmation.timeoutSeconds = rollback.timeoutSeconds
            config.confirmation = confirmation
        }
        try saveUnlocked(config)
        logger.info("Migrated config schema to v2; backup=\(backup.path)")
        return config
    }

    private func saveUnlocked(_ config: AppConfig) throws {
        try ensureDirectory()
        let data = try encoder.encode(config)
        try data.write(to: configFile, options: .atomic)
    }

    private func healthUnlocked() throws -> ConfigHealth {
        guard FileManager.default.fileExists(atPath: healthFile.path) else { return .healthy }
        return try decoder.decode(ConfigHealth.self, from: Data(contentsOf: healthFile))
    }

    private func clearHealthUnlocked() throws {
        if FileManager.default.fileExists(atPath: healthFile.path) {
            try FileManager.default.removeItem(at: healthFile)
        }
    }

    private func backupDamagedConfigUnlocked() throws -> URL {
        let data = try Data(contentsOf: configFile)
        let hash = contentHash(data)
        let backup = configFile.deletingLastPathComponent().appendingPathComponent("config.damaged.\(hash).json")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try data.write(to: backup, options: .atomic)
        }
        try pruneDamagedBackups(keeping: 5)
        return backup
    }

    private func contentHash(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private func pruneDamagedBackups(keeping limit: Int) throws {
        let directory = configFile.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter { $0.lastPathComponent.hasPrefix("config.damaged.") && $0.pathExtension == "json" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for backup in backups.dropFirst(limit) {
            try FileManager.default.removeItem(at: backup)
            logger.info("Removed old damaged config backup: \(backup.path)")
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        try ensureDirectory()
        let descriptor = Darwin.open(lockFile.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw StateStoreError.lockOpenFailed(path: lockFile.path, errno: errno)
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
        let deadline = clock.uptime + lockTimeoutSeconds
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard clock.uptime < deadline else {
                throw StateStoreError.lockTimeout(path: lockFile.path, timeoutSeconds: lockTimeoutSeconds)
            }
            clock.sleep(seconds: 0.01)
        }
        return try body()
    }
}
