import Foundation

public final class LaunchAgentManager {
    private let logger: CHLogger

    public init(logger: CHLogger = CHLogger()) {
        self.logger = logger
    }

    public var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.codexheadless.app.plist")
    }

    public func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    public func setEnabled(_ enabled: Bool, executablePath: String) {
        do {
            try FileManager.default.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if enabled {
                let plist = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>Label</key>
                    <string>com.codexheadless.app</string>
                    <key>ProgramArguments</key>
                    <array>
                        <string>\(executablePath)</string>
                    </array>
                    <key>RunAtLoad</key>
                    <true/>
                </dict>
                </plist>
                """
                try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
                logger.info("Start at Login enabled via LaunchAgent: \(launchAgentURL.path)")
            } else if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try FileManager.default.removeItem(at: launchAgentURL)
                logger.info("Start at Login disabled.")
            }
        } catch {
            logger.error("Failed to update LaunchAgent: \(error.localizedDescription)")
        }
    }
}
