import Foundation

public final class CHLogger {
    public init() {}

    public func info(_ message: String) {
        write("INFO", message)
    }

    public func warn(_ message: String) {
        write("WARN", message)
    }

    public func error(_ message: String) {
        write("ERROR", message)
    }

    private func write(_ level: String, _ message: String) {
        do {
            try CodexHeadlessPaths.ensureDirectories()
            let formatter = ISO8601DateFormatter()
            let line = "[\(formatter.string(from: Date()))] [\(level)] \(message)\n"
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: CodexHeadlessPaths.logFile.path) {
                let handle = try FileHandle(forWritingTo: CodexHeadlessPaths.logFile)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: CodexHeadlessPaths.logFile)
            }
        } catch {
            fputs("CodexHeadless logger failed: \(error)\n", stderr)
        }
    }
}
