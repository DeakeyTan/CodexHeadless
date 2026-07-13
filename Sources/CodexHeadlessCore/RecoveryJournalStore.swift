import Darwin
import Foundation

public enum RecoveryJournalStoreError: LocalizedError {
    case lockOpenFailed(path: String, errno: Int32)
    case lockTimeout(path: String, timeoutSeconds: TimeInterval)
    case damaged(path: String, underlying: Error)
    case unsupportedSchema(Int)
    case checksumMismatch
    case alreadyExists

    public var errorDescription: String? {
        switch self {
        case .lockOpenFailed(let path, let code):
            return "Unable to open recovery journal lock at \(path): errno \(code)."
        case .lockTimeout(let path, let timeout):
            return "Timed out after \(timeout)s waiting for recovery journal lock at \(path)."
        case .damaged(let path, let error):
            return "Recovery journal at \(path) is damaged: \(error.localizedDescription)"
        case .unsupportedSchema(let version):
            return "Recovery journal schema v\(version) is newer than this build supports."
        case .checksumMismatch:
            return "Recovery journal checksum does not match its content."
        case .alreadyExists:
            return "A Recovery Journal already exists and must not be overwritten."
        }
    }
}

public protocol RecoveryJournalStoring: AnyObject {
    func read() throws -> RecoveryJournal?
    func create(operationID: String) throws -> RecoveryJournal
    func update(_ mutation: (inout RecoveryJournal) throws -> Void) throws
    func delete() throws
}

public final class RecoveryJournalStore: RecoveryJournalStoring {
    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
        let operationID: String?
    }
    private static let processLock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger: CHLogger
    private let journalFile: URL
    private let lockFile: URL
    private let lockTimeoutSeconds: TimeInterval
    private let clock: WorkflowClock

    public init(
        logger: CHLogger = CHLogger(),
        journalFile: URL = CodexHeadlessPaths.recoveryJournalFile,
        lockFile: URL = CodexHeadlessPaths.recoveryJournalLockFile,
        lockTimeoutSeconds: TimeInterval = 2,
        clock: WorkflowClock = SystemWorkflowClock()
    ) {
        self.logger = logger
        self.journalFile = journalFile
        self.lockFile = lockFile
        self.lockTimeoutSeconds = lockTimeoutSeconds
        self.clock = clock
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func read() throws -> RecoveryJournal? { try withLock { try readUnlocked() } }

    public func create(operationID: String) throws -> RecoveryJournal {
        try withLock {
            if FileManager.default.fileExists(atPath: journalFile.path) {
                _ = try readUnlocked()
                throw RecoveryJournalStoreError.alreadyExists
            }
            var journal = RecoveryJournal(operationID: operationID, createdAt: clock.now)
            try writeUnlocked(&journal)
            return journal
        }
    }

    public func update(_ mutation: (inout RecoveryJournal) throws -> Void) throws {
        try withLock {
            guard var journal = try readUnlocked() else {
                throw CodexHeadlessError.recoveryJournalUnavailable(message: "Recovery journal is missing.")
            }
            try mutation(&journal)
            journal.updatedAt = clock.now
            try writeUnlocked(&journal)
        }
    }

    public func delete() throws {
        try withLock {
            guard FileManager.default.fileExists(atPath: journalFile.path) else { return }
            _ = try readUnlocked()
            try FileManager.default.removeItem(at: journalFile)
            logger.info("Recovery journal removed after verified Normal state persistence.")
        }
    }

    private func readUnlocked() throws -> RecoveryJournal? {
        try ensureParentDirectory()
        guard FileManager.default.fileExists(atPath: journalFile.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: journalFile)
        } catch {
            backupDamagedJournalIfPresent()
            throw RecoveryJournalStoreError.damaged(path: journalFile.path, underlying: error)
        }
        let probe: SchemaProbe
        do {
            probe = try decoder.decode(SchemaProbe.self, from: data)
        } catch {
            backupDamagedJournalIfPresent()
            throw RecoveryJournalStoreError.damaged(path: journalFile.path, underlying: error)
        }
        guard probe.schemaVersion <= RecoveryJournal.currentSchemaVersion else {
            // Future journals are immutable evidence for this older build.
            throw RecoveryJournalStoreError.unsupportedSchema(probe.schemaVersion)
        }
        do {
            let journal = try decoder.decode(RecoveryJournal.self, from: data)
            guard journal.checksum == checksum(for: journal) else {
                throw RecoveryJournalStoreError.checksumMismatch
            }
            return journal
        } catch {
            backupDamagedJournalIfPresent()
            if let journalError = error as? RecoveryJournalStoreError {
                throw RecoveryJournalStoreError.damaged(path: journalFile.path, underlying: journalError)
            }
            throw RecoveryJournalStoreError.damaged(path: journalFile.path, underlying: error)
        }
    }

    private func writeUnlocked(_ journal: inout RecoveryJournal) throws {
        try ensureParentDirectory()
        journal.checksum = checksum(for: journal)
        try encoder.encode(journal).write(to: journalFile, options: .atomic)
    }

    private func checksum(for journal: RecoveryJournal) -> String {
        var copy = journal
        copy.checksum = nil
        return Self.contentHash((try? encoder.encode(copy)) ?? Data())
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        try ensureParentDirectory()
        let descriptor = Darwin.open(lockFile.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw RecoveryJournalStoreError.lockOpenFailed(path: lockFile.path, errno: errno)
        }
        defer { _ = flock(descriptor, LOCK_UN); _ = Darwin.close(descriptor) }
        let deadline = clock.uptime + lockTimeoutSeconds
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else {
                throw RecoveryJournalStoreError.lockOpenFailed(path: lockFile.path, errno: errno)
            }
            guard clock.uptime < deadline else {
                throw RecoveryJournalStoreError.lockTimeout(path: lockFile.path, timeoutSeconds: lockTimeoutSeconds)
            }
            clock.sleep(seconds: 0.01)
        }
        return try body()
    }

    private func ensureParentDirectory() throws {
        try FileManager.default.createDirectory(at: journalFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func backupDamagedJournalIfPresent() {
        guard FileManager.default.fileExists(atPath: journalFile.path),
              let data = try? Data(contentsOf: journalFile) else { return }
        let hash = Self.contentHash(data)
        let backup = journalFile.deletingLastPathComponent().appendingPathComponent("recovery-journal.damaged.\(hash).json")
        do {
            if !FileManager.default.fileExists(atPath: backup.path) {
                try data.write(to: backup, options: .atomic)
                logger.error("Backed up damaged recovery journal to \(backup.path).")
            }
            let backups = try FileManager.default.contentsOfDirectory(
                at: journalFile.deletingLastPathComponent(),
                includingPropertiesForKeys: [.contentModificationDateKey]
            ).filter { $0.lastPathComponent.hasPrefix("recovery-journal.damaged.") && $0.pathExtension == "json" }
                .sorted {
                    let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return lhs > rhs
                }
            for old in backups.dropFirst(5) { try FileManager.default.removeItem(at: old) }
        } catch {
            logger.error("Failed to back up damaged recovery journal: \(error.localizedDescription)")
        }
    }

    private static func contentHash(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        return String(format: "%016llx", hash)
    }
}
