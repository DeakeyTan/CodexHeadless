import CryptoKit
import Darwin
import Foundation

public enum InternalHelperKind: String, Codable, CaseIterable {
    case keepAwakeHost = "keep-awake-host"
    case virtualDisplayHost = "virtual-display-host"
    case softDisconnectApply = "soft-disconnect-apply"
    case touchBarApply = "touchbar-apply"
}

public struct HelperCapabilityRecord: Codable, Equatable {
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public var capabilityID: String
    public var operationID: String
    public var helperKind: InternalHelperKind
    public var nonceHash: String
    public var expiresAt: Date
    public var expectedParentPID: Int32
    public var expectedExecutablePath: String
    public var expectedExecutableFileIdentity: String?
    public var consumed: Bool
    public var expectedJournalStage: RecoveryJournalStage?
}

public struct HelperLaunchCapability: Equatable {
    public var capabilityID: String
    public var nonce: String
    public var operationID: String
}

public enum HelperCapabilityError: LocalizedError {
    case missing
    case unsupportedFutureSchema(Int)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .missing: "Internal helper capability is missing."
        case .unsupportedFutureSchema(let version): "Internal helper capability schema v\(version) requires a newer CodexHeadless build."
        case .invalid(let reason): "Internal helper authorization failed: \(reason)"
        }
    }
}

public final class HelperCapabilityStore {
    private struct SchemaProbe: Decodable { let schemaVersion: Int }
    private static let processLock = NSLock()
    private let directory: URL
    private let lockFile: URL
    private let clock: WorkflowClock
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let journalStore: RecoveryJournalStoring

    public init(
        directory: URL = CodexHeadlessPaths.helperCapabilitiesDirectory,
        lockFile: URL = CodexHeadlessPaths.helperCapabilitiesLockFile,
        clock: WorkflowClock = SystemWorkflowClock(),
        journalStore: RecoveryJournalStoring = RecoveryJournalStore()
    ) {
        self.directory = directory
        self.lockFile = lockFile
        self.clock = clock
        self.journalStore = journalStore
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func reserve(
        kind: InternalHelperKind,
        operationID: String,
        expectedParentPID: Int32 = getpid(),
        expectedExecutablePath: String,
        ttlSeconds: TimeInterval = 15
    ) throws -> HelperLaunchCapability {
        guard let journal = try journalStore.read(), journal.operationID == operationID else {
            throw HelperCapabilityError.invalid("active Recovery Journal operation mismatch")
        }
        guard Self.stage(journal.stage, permits: kind) else {
            throw HelperCapabilityError.invalid("Recovery Journal stage \(journal.stage.rawValue) does not permit \(kind.rawValue)")
        }
        try pruneExpiredAndConsumed()
        let capabilityID = UUID().uuidString.lowercased()
        let nonce = UUID().uuidString.lowercased() + UUID().uuidString.lowercased()
        let canonicalPath = URL(fileURLWithPath: expectedExecutablePath).resolvingSymlinksInPath().path
        let record = HelperCapabilityRecord(
            schemaVersion: HelperCapabilityRecord.currentSchemaVersion,
            capabilityID: capabilityID,
            operationID: operationID,
            helperKind: kind,
            nonceHash: Self.hash(nonce),
            expiresAt: clock.now.addingTimeInterval(ttlSeconds),
            expectedParentPID: expectedParentPID,
            expectedExecutablePath: canonicalPath,
            expectedExecutableFileIdentity: Self.fileIdentity(path: canonicalPath),
            consumed: false,
            expectedJournalStage: journal.stage
        )
        try withLock {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(record).write(to: file(for: capabilityID), options: .atomic)
        }
        return HelperLaunchCapability(capabilityID: capabilityID, nonce: nonce, operationID: operationID)
    }

    @discardableResult
    public func consume(
        capabilityID: String,
        nonce: String,
        operationID: String,
        kind: InternalHelperKind,
        actualParentPID: Int32 = getppid(),
        actualExecutablePath: String = CommandLine.arguments.first ?? ""
    ) throws -> HelperCapabilityRecord {
        try withLock {
            let url = file(for: capabilityID)
            guard FileManager.default.fileExists(atPath: url.path) else { throw HelperCapabilityError.missing }
            let data = try Data(contentsOf: url)
            let probe = try decoder.decode(SchemaProbe.self, from: data)
            guard probe.schemaVersion <= HelperCapabilityRecord.currentSchemaVersion else {
                throw HelperCapabilityError.unsupportedFutureSchema(probe.schemaVersion)
            }
            var record = try decoder.decode(HelperCapabilityRecord.self, from: data)
            guard !record.consumed else { throw HelperCapabilityError.invalid("capability has already been consumed") }
            guard record.expiresAt >= clock.now else { throw HelperCapabilityError.invalid("capability expired") }
            guard record.operationID == operationID else { throw HelperCapabilityError.invalid("operation mismatch") }
            guard record.helperKind == kind else { throw HelperCapabilityError.invalid("helper kind mismatch") }
            guard record.expectedParentPID == actualParentPID else { throw HelperCapabilityError.invalid("parent PID mismatch") }
            guard record.nonceHash == Self.hash(nonce) else { throw HelperCapabilityError.invalid("nonce mismatch") }
            let actualPath = URL(fileURLWithPath: actualExecutablePath).resolvingSymlinksInPath().path
            guard record.expectedExecutablePath == actualPath else { throw HelperCapabilityError.invalid("executable path mismatch") }
            if let expectedIdentity = record.expectedExecutableFileIdentity,
               Self.fileIdentity(path: actualPath) != expectedIdentity {
                throw HelperCapabilityError.invalid("executable file identity mismatch")
            }
            guard let expectedStage = record.expectedJournalStage else {
                throw HelperCapabilityError.invalid("capability is not bound to a Recovery Journal stage")
            }
            guard let journal = try journalStore.read(), journal.operationID == record.operationID else {
                throw HelperCapabilityError.invalid("active Recovery Journal operation mismatch")
            }
            guard journal.stage == expectedStage else {
                throw HelperCapabilityError.invalid("Recovery Journal stage mismatch: expected \(expectedStage.rawValue), found \(journal.stage.rawValue)")
            }
            guard Self.stage(journal.stage, permits: kind) else {
                throw HelperCapabilityError.invalid("Recovery Journal stage does not permit this helper kind")
            }
            record.consumed = true
            try FileManager.default.removeItem(at: url)
            return record
        }
    }

    public func pruneExpiredAndConsumed() throws {
        try withLock {
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                let data = try Data(contentsOf: url)
                guard let probe = try? decoder.decode(SchemaProbe.self, from: data),
                      probe.schemaVersion <= HelperCapabilityRecord.currentSchemaVersion,
                      let record = try? decoder.decode(HelperCapabilityRecord.self, from: data) else { continue }
                if record.consumed || record.expiresAt < clock.now {
                    try FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    private func file(for capabilityID: String) -> URL {
        directory.appendingPathComponent("\(capabilityID).json")
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        try FileManager.default.createDirectory(at: lockFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(lockFile.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw HelperCapabilityError.invalid("capability lock could not be opened") }
        defer { _ = flock(descriptor, LOCK_UN); _ = Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw HelperCapabilityError.invalid("capability lock could not be acquired") }
        return try body()
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func stage(_ stage: RecoveryJournalStage, permits kind: InternalHelperKind) -> Bool {
        switch kind {
        case .keepAwakeHost:
            return stage == .enabling
        case .virtualDisplayHost:
            return stage == .enabling || stage == .keepAwakeStarted
        case .softDisconnectApply:
            return stage == .handoffCommitted || stage == .restoringPhysicalDisplay
        case .touchBarApply:
            return stage == .handoffCommitted || stage == .builtInSoftDisconnected || stage == .cleanupInProgress
        }
    }

    private static func fileIdentity(path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let volume = attributes[.systemNumber] as? NSNumber,
              let file = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return "\(volume.uint64Value):\(file.uint64Value)"
    }
}
