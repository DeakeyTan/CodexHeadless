import Foundation

public enum CodexHeadlessPaths {
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexHeadless", isDirectory: true)
    }

    public static var configFile: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    public static var configLockFile: URL {
        supportDirectory.appendingPathComponent("config.lock")
    }

    public static var stateFile: URL {
        supportDirectory.appendingPathComponent("state.json")
    }

    public static var stateLockFile: URL {
        supportDirectory.appendingPathComponent("state.lock")
    }

    public static var recoveryJournalFile: URL {
        supportDirectory.appendingPathComponent("recovery-journal.json")
    }

    public static var recoveryJournalLockFile: URL {
        supportDirectory.appendingPathComponent("recovery-journal.lock")
    }

    public static var operationLockFile: URL {
        supportDirectory.appendingPathComponent("operation.lock")
    }

    public static var helperCapabilitiesDirectory: URL {
        supportDirectory.appendingPathComponent("helper-capabilities", isDirectory: true)
    }

    public static var helperCapabilitiesLockFile: URL {
        supportDirectory.appendingPathComponent("helper-capabilities.lock")
    }

    public static var configHealthFile: URL {
        supportDirectory.appendingPathComponent("config.health.json")
    }

    public static var snapshotFile: URL {
        supportDirectory.appendingPathComponent("snapshot.json")
    }

    public static var touchBarControlStripBackupFile: URL {
        supportDirectory.appendingPathComponent("touchbar-controlstrip-backup.plist")
    }

    public static var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CodexHeadless.log")
    }

    public static func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: logFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
