import Darwin
import Foundation

public enum StateStoreError: LocalizedError {
    case lockOpenFailed(path: String, errno: Int32)
    case lockTimeout(path: String, timeoutSeconds: TimeInterval)
    case corruptedState(path: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .lockOpenFailed(let path, let code):
            return "Unable to open state lock at \(path): errno \(code)."
        case .lockTimeout(let path, let timeout):
            return "Timed out after \(timeout)s waiting for state lock at \(path)."
        case .corruptedState(let path, let error):
            return "Runtime state at \(path) is damaged: \(error.localizedDescription)"
        }
    }
}

public protocol RuntimeStateStoring: AnyObject {
    func load() -> RuntimeState
    func save(_ state: RuntimeState) throws
    func read() throws -> RuntimeState
    func write(_ state: RuntimeState) throws
    func transaction<T>(_ mutation: (inout RuntimeState) throws -> T) throws -> T
    func replaceCorruptedStateAfterVerifiedRecovery(_ state: RuntimeState) throws
    func bestEffortUpdate(_ mutation: (inout RuntimeState) -> Void)
}

public final class StateStore: RuntimeStateStoring {
    private static let processLock = NSLock()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger: CHLogger
    private let stateFile: URL
    private let lockFile: URL
    private let lockTimeoutSeconds: TimeInterval
    private let clock: WorkflowClock

    public init(
        logger: CHLogger = CHLogger(),
        stateFile: URL = CodexHeadlessPaths.stateFile,
        lockFile: URL = CodexHeadlessPaths.stateLockFile,
        lockTimeoutSeconds: TimeInterval = 2,
        clock: WorkflowClock = SystemWorkflowClock()
    ) {
        self.logger = logger
        self.stateFile = stateFile
        self.lockFile = lockFile
        self.lockTimeoutSeconds = lockTimeoutSeconds
        self.clock = clock
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func read() throws -> RuntimeState {
        try withLock { try loadUnlocked(createIfMissing: true) }
    }

    public func write(_ state: RuntimeState) throws {
        try withLock { try saveUnlocked(state) }
    }

    public func transaction<T>(_ mutation: (inout RuntimeState) throws -> T) throws -> T {
        try withLock {
            var state = try loadUnlocked(createIfMissing: true)
            let result = try mutation(&state)
            try saveUnlocked(state)
            return result
        }
    }

    public func replaceCorruptedStateAfterVerifiedRecovery(_ state: RuntimeState) throws {
        try withLock {
            if FileManager.default.fileExists(atPath: stateFile.path) {
                do {
                    _ = try loadUnlocked(createIfMissing: false)
                } catch StateStoreError.corruptedState {
                    // This explicit API is the only path allowed to replace damaged state.
                }
            }
            try saveUnlocked(state)
        }
    }

    // Compatibility helpers for status/UI paths. Critical workflows should use
    // read/write/transaction so persistence failures remain visible to callers.
    public func load() -> RuntimeState {
        do {
            return try read()
        } catch {
            logger.error("Failed to load runtime state: \(error.localizedDescription)")
            return .recoveryRequired(message: error.localizedDescription, now: clock.now)
        }
    }

    public func save(_ state: RuntimeState) throws {
        try write(state)
    }

    public func bestEffortUpdate(_ block: (inout RuntimeState) -> Void) {
        do {
            try transaction { state in block(&state) }
        } catch {
            logger.error("Failed to update runtime state: \(error.localizedDescription)")
        }
    }

    private func loadUnlocked(createIfMissing: Bool) throws -> RuntimeState {
        try ensureParentDirectory()
        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            let state = RuntimeState.default
            if createIfMissing {
                try saveUnlocked(state)
            }
            return state
        }

        do {
            let data = try Data(contentsOf: stateFile)
            return try decoder.decode(RuntimeState.self, from: data)
        } catch {
            backupDamagedStateIfPresent()
            throw StateStoreError.corruptedState(path: stateFile.path, underlying: error)
        }
    }

    private func saveUnlocked(_ state: RuntimeState) throws {
        try ensureParentDirectory()
        let data = try encoder.encode(state)
        try data.write(to: stateFile, options: .atomic)
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }

        try ensureParentDirectory()
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
            guard errno == EWOULDBLOCK || errno == EAGAIN else {
                throw StateStoreError.lockOpenFailed(path: lockFile.path, errno: errno)
            }
            guard clock.uptime < deadline else {
                throw StateStoreError.lockTimeout(path: lockFile.path, timeoutSeconds: lockTimeoutSeconds)
            }
            clock.sleep(seconds: 0.01)
        }
        return try body()
    }

    private func ensureParentDirectory() throws {
        try FileManager.default.createDirectory(
            at: stateFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if lockFile.deletingLastPathComponent() != stateFile.deletingLastPathComponent() {
            try FileManager.default.createDirectory(
                at: lockFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
    }

    private func backupDamagedStateIfPresent() {
        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: stateFile)
            let hash = contentHash(data)
            let backup = stateFile.deletingLastPathComponent()
                .appendingPathComponent("state.damaged.\(hash).json")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try data.write(to: backup, options: .atomic)
                logger.error("Backed up damaged runtime state to \(backup.path).")
            }
            try pruneDamagedBackups(keeping: 5)
        } catch {
            logger.error("Failed to back up damaged runtime state: \(error.localizedDescription)")
        }
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
        let directory = stateFile.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter { $0.lastPathComponent.hasPrefix("state.damaged.") && $0.pathExtension == "json" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for backup in backups.dropFirst(limit) {
            try FileManager.default.removeItem(at: backup)
            logger.info("Removed old damaged state backup: \(backup.path)")
        }
    }
}
