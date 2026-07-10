import CoreGraphics
import Foundation

public struct DisplayLayoutSnapshot: Codable {
    public var version: Int
    public var profileKey: String
    public var createdAt: Date
    public var reason: String
    public var displays: [DisplayLayoutEntry]

    public static let currentVersion = 1

    public var mainDisplay: DisplayLayoutEntry? {
        displays.first { $0.isMain }
    }
}

public struct DisplayLayoutSnapshotCollection: Codable {
    public var version: Int
    public var updatedAt: Date
    public var activeProfileKey: String?
    public var snapshotsByProfile: [String: DisplayLayoutSnapshot]

    public static let currentVersion = 1
}

public struct DisplayLayoutEntry: Codable {
    public var id: UInt32
    public var isMain: Bool
    public var isBuiltIn: Bool
    public var isManagedVirtual: Bool
    public var isActive: Bool
    public var isOnline: Bool
    public var width: Int
    public var height: Int
    public var originX: Int
    public var originY: Int
    public var vendorNumber: UInt32
    public var modelNumber: UInt32
}

public struct DisplayLayoutRestoreResult {
    public var appliedCount: Int
    public var skippedCount: Int
    public var message: String
}

public final class DisplayLayoutStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger: CHLogger
    private let fileURL: URL

    public init(
        logger: CHLogger = CHLogger(),
        fileURL: URL = CodexHeadlessPaths.snapshotFile
    ) {
        self.logger = logger
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func capture(from displays: [DisplayInfo], reason: String, includeManagedVirtual: Bool = false) -> DisplayLayoutSnapshot {
        let profileKey = Self.profileKey(for: displays)
        let entries = displays
            .filter { includeManagedVirtual || !$0.isManagedVirtual }
            .map { display in
                DisplayLayoutEntry(
                    id: display.id,
                    isMain: display.isMain,
                    isBuiltIn: display.isBuiltIn,
                    isManagedVirtual: display.isManagedVirtual,
                    isActive: display.isActive,
                    isOnline: display.isOnline,
                    width: display.width,
                    height: display.height,
                    originX: display.originX,
                    originY: display.originY,
                    vendorNumber: display.vendorNumber,
                    modelNumber: display.modelNumber
                )
            }

        return DisplayLayoutSnapshot(
            version: DisplayLayoutSnapshot.currentVersion,
            profileKey: profileKey,
            createdAt: Date(),
            reason: reason,
            displays: entries
        )
    }

    public func save(_ snapshot: DisplayLayoutSnapshot) throws {
        try CodexHeadlessPaths.ensureDirectories()
        var collection = loadCollectionIfPresent()
        collection.updatedAt = Date()
        collection.activeProfileKey = snapshot.profileKey
        collection.snapshotsByProfile[snapshot.profileKey] = snapshot
        let data = try encoder.encode(collection)
        try data.write(to: fileURL, options: .atomic)
        logger.info("Saved display layout snapshot: profile=\(snapshot.profileKey) path=\(fileURL.path)")
    }

    public func load() throws -> DisplayLayoutSnapshot {
        let collection = try loadCollection()
        if let activeProfileKey = collection.activeProfileKey,
           let snapshot = collection.snapshotsByProfile[activeProfileKey] {
            return snapshot
        }
        if let snapshot = collection.snapshotsByProfile.values.sorted(by: { $0.createdAt > $1.createdAt }).first {
            return snapshot
        }
        throw NSError(domain: "CodexHeadless.DisplayLayout", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "No display layout snapshot is available."
        ])
    }

    public func loadMatching(displays: [DisplayInfo]) throws -> DisplayLayoutSnapshot {
        let collection = try loadCollection()
        let profileKey = Self.profileKey(for: displays)
        if let snapshot = collection.snapshotsByProfile[profileKey] {
            logger.info("Loaded display layout snapshot for current profile: \(profileKey)")
            return snapshot
        }
        if let activeProfileKey = collection.activeProfileKey,
           let snapshot = collection.snapshotsByProfile[activeProfileKey] {
            logger.warn("No exact display layout snapshot for profile \(profileKey); using active profile \(activeProfileKey).")
            return snapshot
        }
        return try load()
    }

    public func saveSingleSnapshot(_ snapshot: DisplayLayoutSnapshot) throws {
        try CodexHeadlessPaths.ensureDirectories()
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        logger.info("Exported display layout snapshot: profile=\(snapshot.profileKey) path=\(fileURL.path)")
    }

    public func loadSingleSnapshot() throws -> DisplayLayoutSnapshot {
        let data = try Data(contentsOf: fileURL)
        if let snapshot = try? decoder.decode(DisplayLayoutSnapshot.self, from: data) {
            return snapshot
        }
        let collection = try decoder.decode(DisplayLayoutSnapshotCollection.self, from: data)
        if let activeProfileKey = collection.activeProfileKey,
           let snapshot = collection.snapshotsByProfile[activeProfileKey] {
            return snapshot
        }
        if let snapshot = collection.snapshotsByProfile.values.sorted(by: { $0.createdAt > $1.createdAt }).first {
            return snapshot
        }
        throw NSError(domain: "CodexHeadless.DisplayLayout", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "No display layout snapshot is available in the selected file."
        ])
    }

    public func loadCollection() throws -> DisplayLayoutSnapshotCollection {
        let data = try Data(contentsOf: fileURL)
        if let collection = try? decoder.decode(DisplayLayoutSnapshotCollection.self, from: data) {
            return collection
        }
        return try decoder.decode(DisplayLayoutSnapshot.self, from: data)
            .asCollection()
    }

    public static func profileKey(for displays: [DisplayInfo]) -> String {
        let parts = displays
            .filter { $0.isActive && !$0.isManagedVirtual }
            .map { display -> String in
                let type = display.isBuiltIn ? "builtin" : "external"
                return "\(type)-\(display.vendorNumber)-\(display.modelNumber)-\(display.width)x\(display.height)"
            }
            .sorted()
        return parts.isEmpty ? "no-physical-display" : parts.joined(separator: "_")
    }

    public func saveCurrentLayout(
        displayManager: DisplayManager,
        reason: String,
        includeManagedVirtual: Bool = false
    ) {
        let displays = displayManager.displays()
        logger.info("Displays before layout snapshot: \(displayManager.compactStatus(displays: displays))")
        do {
            let snapshot = capture(
                from: displays,
                reason: reason,
                includeManagedVirtual: includeManagedVirtual
            )
            try save(snapshot)
        } catch {
            logger.warn("Failed to save display layout snapshot: \(error.localizedDescription)")
        }
    }

    private func loadCollectionIfPresent() -> DisplayLayoutSnapshotCollection {
        do {
            return try loadCollection()
        } catch {
            return DisplayLayoutSnapshotCollection(
                version: DisplayLayoutSnapshotCollection.currentVersion,
                updatedAt: Date(),
                activeProfileKey: nil,
                snapshotsByProfile: [:]
            )
        }
    }
}

private extension DisplayLayoutSnapshot {
    func asCollection() -> DisplayLayoutSnapshotCollection {
        DisplayLayoutSnapshotCollection(
            version: DisplayLayoutSnapshotCollection.currentVersion,
            updatedAt: createdAt,
            activeProfileKey: profileKey,
            snapshotsByProfile: [profileKey: self]
        )
    }
}
