import Foundation

public enum CodexHeadlessPaths {
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexHeadless", isDirectory: true)
    }

    public static var configFile: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    public static var stateFile: URL {
        supportDirectory.appendingPathComponent("state.json")
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
