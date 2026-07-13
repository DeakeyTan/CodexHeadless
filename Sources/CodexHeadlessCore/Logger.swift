import Darwin
import Foundation

public final class DiagnosticLoggingPolicy {
    public static let environmentKey = "CODEX_HEADLESS_DIAGNOSTIC_LOGGING"
    public static let shared = DiagnosticLoggingPolicy(
        enabled: ProcessInfo.processInfo.environment[environmentKey] == "1",
        propagatesToEnvironment: true
    )

    private let lock = NSLock()
    private let propagatesToEnvironment: Bool
    private var enabled: Bool

    public init(enabled: Bool, propagatesToEnvironment: Bool = false) {
        self.enabled = enabled
        self.propagatesToEnvironment = propagatesToEnvironment
        if propagatesToEnvironment { setenv(Self.environmentKey, enabled ? "1" : "0", 1) }
    }

    public var isEnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled
    }

    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        self.enabled = enabled
        if propagatesToEnvironment { setenv(Self.environmentKey, enabled ? "1" : "0", 1) }
        lock.unlock()
    }

    func beginWriteIfEnabled() -> Bool {
        lock.lock()
        guard enabled else { lock.unlock(); return false }
        return true
    }

    func endWrite() {
        lock.unlock()
    }
}

public final class CHLogger {
    private static let processLock = NSLock()
    private static let maximumBytes: UInt64 = 5 * 1024 * 1024
    private static let retainedFiles = 3

    private let logFile: URL
    private let policy: DiagnosticLoggingPolicy

    public convenience init() {
        self.init(logFile: CodexHeadlessPaths.logFile, policy: .shared)
    }

    public init(logFile: URL, policy: DiagnosticLoggingPolicy = .shared) {
        self.logFile = logFile
        self.policy = policy
    }

    public func info(_ message: String) { write("INFO", message) }
    public func warn(_ message: String) { write("WARN", message) }
    public func error(_ message: String) { write("ERROR", message) }

    private func write(_ level: String, _ message: String) {
        guard policy.beginWriteIfEnabled() else { return }
        defer { policy.endWrite() }
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        do {
            try FileManager.default.createDirectory(
                at: logFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let lockPath = logFile.path + ".lock"
            let lockDescriptor = Darwin.open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard lockDescriptor >= 0 else { throw LoggerError.openLock }
            defer {
                _ = flock(lockDescriptor, LOCK_UN)
                _ = Darwin.close(lockDescriptor)
            }
            guard flock(lockDescriptor, LOCK_EX) == 0 else { throw LoggerError.lock }

            try Self.rotateIfNeeded(logFile: logFile)
            let formatter = ISO8601DateFormatter()
            let line = "[\(formatter.string(from: Date()))] [\(level)] \(message)\n"
            let descriptor = Darwin.open(
                logFile.path,
                O_CREAT | O_WRONLY | O_APPEND,
                S_IRUSR | S_IWUSR
            )
            guard descriptor >= 0 else { throw LoggerError.openLog }
            defer { _ = Darwin.close(descriptor) }
            let data = Data(line.utf8)
            let written = data.withUnsafeBytes { bytes -> Int in
                guard let baseAddress = bytes.baseAddress else { return 0 }
                return Darwin.write(descriptor, baseAddress, bytes.count)
            }
            guard written == data.count else { throw LoggerError.shortWrite }
            if level == "ERROR" || message.contains("operation finished") || message.contains("Normal Mode restored") {
                _ = fsync(descriptor)
            }
        } catch {
            fputs("CodexHeadless logger failed: \(error)\n", stderr)
        }
    }

    private static func rotateIfNeeded(logFile: URL) throws {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: logFile.path)[.size] as? NSNumber)?.uint64Value,
              size >= maximumBytes else { return }
        let manager = FileManager.default
        for index in stride(from: retainedFiles, through: 1, by: -1) {
            let destination = URL(fileURLWithPath: logFile.path + ".\(index)")
            if index == retainedFiles, manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            let source = index == 1
                ? logFile
                : URL(fileURLWithPath: logFile.path + ".\(index - 1)")
            if manager.fileExists(atPath: source.path) {
                try manager.moveItem(at: source, to: destination)
            }
        }
    }
}

private enum LoggerError: Error {
    case openLock
    case lock
    case openLog
    case shortWrite
}
