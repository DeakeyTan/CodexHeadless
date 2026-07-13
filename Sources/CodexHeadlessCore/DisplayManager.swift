import CoreGraphics
import Foundation

public struct DisplayInfo: Codable {
    public var id: UInt32
    public var isMain: Bool
    public var isBuiltIn: Bool
    public var isActive: Bool
    public var isOnline: Bool
    public var width: Int
    public var height: Int
    public var originX: Int
    public var originY: Int
    public var vendorNumber: UInt32
    public var modelNumber: UInt32

    public var isManagedVirtual: Bool {
        vendorNumber == 0xC0DE && modelNumber == 0x0511
    }

    public var typeLabel: String {
        if isBuiltIn {
            return "Built-in"
        }
        return isManagedVirtual ? "Managed Virtual" : "External / Dummy"
    }
}

public struct DisplayTakeoverVerification: Equatable {
    public var displayID: UInt32
    public var exists: Bool
    public var physical: Bool
    public var active: Bool
    public var online: Bool
    public var main: Bool
    public var stable: Bool

    public var safeToDestroyVirtualDisplay: Bool {
        exists && physical && active && online && main && stable
    }

    public var summary: String {
        "displayID=\(displayID), exists=\(exists), physical=\(physical), active=\(active), online=\(online), main=\(main), stable=\(stable), safe=\(safeToDestroyVirtualDisplay)"
    }
}

public final class DisplayManager {
    private let logger: CHLogger
    private let clock: WorkflowClock

    public init(logger: CHLogger = CHLogger(), clock: WorkflowClock = SystemWorkflowClock()) {
        self.logger = logger
        self.clock = clock
    }

    public func displays() -> [DisplayInfo] {
        let displayIDs = Array(Set(onlineDisplayIDs() + activeDisplayIDs())).sorted()
        return displayIDs.map { id in
            displayInfo(id: id)
        }
    }

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &displayIDs, &count)
        return displayIDs
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displayIDs, &count)
        return displayIDs
    }

    private func displayInfo(id: CGDirectDisplayID) -> DisplayInfo {
        let bounds = CGDisplayBounds(id)
        return DisplayInfo(
            id: id,
            isMain: id == CGMainDisplayID(),
            isBuiltIn: CGDisplayIsBuiltin(id) != 0,
            isActive: CGDisplayIsActive(id) != 0,
            isOnline: CGDisplayIsOnline(id) != 0,
            width: Int(bounds.width),
            height: Int(bounds.height),
            originX: Int(bounds.origin.x),
            originY: Int(bounds.origin.y),
            vendorNumber: CGDisplayVendorNumber(id),
            modelNumber: CGDisplayModelNumber(id)
        )
    }

    private func syntheticManagedVirtualDisplay(id: UInt32, resolution: Resolution) -> DisplayInfo {
        DisplayInfo(
            id: id,
            isMain: id == CGMainDisplayID(),
            isBuiltIn: false,
            isActive: true,
            isOnline: true,
            width: resolution.width,
            height: resolution.height,
            originX: 0,
            originY: 0,
            vendorNumber: 0xC0DE,
            modelNumber: 0x0511
        )
    }

    public func hasAlternativeDisplay() -> Bool {
        preferredExternalDisplay() != nil
    }

    public func preferredExternalDisplay() -> DisplayInfo? {
        displays().first {
            !$0.isBuiltIn
                && !$0.isManagedVirtual
                && $0.isActive
                && $0.isOnline
        }
    }

    public func display(id: UInt32) -> DisplayInfo? {
        if let display = displays().first(where: { $0.id == id }) {
            return display
        }

        let info = displayInfo(id: id)
        guard info.width > 0,
              info.height > 0,
              !info.isBuiltIn else {
            return nil
        }
        return info
    }

    public func managedVirtualDisplay() -> DisplayInfo? {
        displays().first {
            !$0.isBuiltIn
                && $0.isActive
                && $0.isManagedVirtual
        }
    }

    @discardableResult
    public func waitForDisplay(id: UInt32, present expectedPresent: Bool, timeoutSeconds: TimeInterval = 2) -> Bool {
        let deadline = clock.uptime + timeoutSeconds
        while clock.uptime < deadline {
            let present = displays().contains { $0.id == id }
            if present == expectedPresent {
                return true
            }
            clock.sleep(seconds: 0.15)
        }

        let present = displays().contains { $0.id == id }
        return present == expectedPresent
    }

    public func setMainDisplayToPreferredExternal() throws -> Bool {
        guard let target = preferredExternalDisplay() else {
            logger.warn("No external or dummy display available to become main display.")
            return false
        }

        return try setMainDisplay(id: target.id, reason: "preferred external/dummy")
    }

    public func setMainDisplayToRestorePriority(managedVirtualDisplayID: UInt32?) throws {
        guard let target = restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID) else {
            logger.warn("No active displays available while restoring main display priority.")
            return
        }

        if target.isMain {
            logger.info("Restore main display priority already satisfied: \(target.id)")
            return
        }

        _ = try setMainDisplay(id: target.id, reason: "restore priority")
    }

    public func restorePriorityDisplay(managedVirtualDisplayID: UInt32?) -> DisplayInfo? {
        let currentDisplays = displays().filter { $0.isActive }
        return currentDisplays.first {
            !$0.isBuiltIn && $0.id != managedVirtualDisplayID && !$0.isManagedVirtual
        } ?? currentDisplays.first {
            $0.isBuiltIn
        } ?? currentDisplays.first {
            $0.id != managedVirtualDisplayID
        }
    }

    public func waitForRestorePriorityDisplay(
        managedVirtualDisplayID: UInt32?,
        timeoutSeconds: TimeInterval
    ) -> DisplayInfo? {
        let deadline = clock.uptime + timeoutSeconds
        while clock.uptime < deadline {
            if let display = restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID) {
                return display
            }
            clock.sleep(seconds: 0.2)
        }
        return restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID)
    }

    public func verifyPhysicalTakeover(
        displayID: UInt32,
        managedVirtualDisplayID: UInt32?,
        stabilizationSeconds: TimeInterval
    ) -> DisplayTakeoverVerification {
        let initial = displays().first { $0.id == displayID }
        if stabilizationSeconds > 0 {
            clock.sleep(seconds: stabilizationSeconds)
        }
        let final = displays().first { $0.id == displayID }
        let isPhysical: (DisplayInfo?) -> Bool = { display in
            guard let display else { return false }
            return display.id != managedVirtualDisplayID && !display.isManagedVirtual
        }
        let verification = DisplayTakeoverVerification(
            displayID: displayID,
            exists: final != nil,
            physical: isPhysical(final),
            active: final?.isActive == true,
            online: final?.isOnline == true,
            main: final?.isMain == true,
            stable: initial != nil && final != nil && isPhysical(initial)
        )
        logger.info("[Safety] physical takeover verification: \(verification.summary)")
        return verification
    }

    public func setMainDisplay(
        id targetID: UInt32,
        reason: String = "requested display",
        fallbackResolution: Resolution? = nil
    ) throws -> Bool {
        guard let target = display(id: targetID) ?? fallbackResolution.map({ syntheticManagedVirtualDisplay(id: targetID, resolution: $0) }),
              target.isActive,
              target.isBuiltIn || target.isOnline || target.isManagedVirtual else {
            logger.warn("Display \(targetID) is not an active external/dummy/virtual display.")
            return false
        }

        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            throw CodexHeadlessError.displayOperation(message: "Failed to begin display configuration: \(beginError.rawValue).")
        }

        var currentDisplays = displays()
        if !currentDisplays.contains(where: { $0.id == target.id }) {
            currentDisplays.append(target)
        }
        for display in currentDisplays {
            if display.id == target.id {
                CGConfigureDisplayOrigin(config, CGDirectDisplayID(display.id), 0, 0)
            } else if display.isActive {
                CGConfigureDisplayOrigin(config, CGDirectDisplayID(display.id), Int32(target.width), 0)
            }
        }

        let completeError = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeError == .success else {
            throw CodexHeadlessError.displayOperation(message: "Failed to complete display configuration: \(completeError.rawValue).")
        }

        logger.info("Set \(reason) as main display: \(target.id)")
        return true
    }

    public func restoreLayout(
        from snapshot: DisplayLayoutSnapshot,
        managedVirtualDisplayID: UInt32? = nil
    ) throws -> DisplayLayoutRestoreResult {
        let currentDisplays = displays().filter { $0.isActive }
        let currentPhysicalDisplays = currentDisplays.filter {
            !$0.isManagedVirtual && $0.id != managedVirtualDisplayID
        }
        let physicalSnapshotEntries = snapshot.displays.filter {
            !$0.isManagedVirtual && $0.id != managedVirtualDisplayID
        }
        let matches = matchLayoutEntries(physicalSnapshotEntries, to: currentPhysicalDisplays)

        guard !matches.isEmpty else {
            let message = "No displays from the saved layout snapshot are currently active."
            logger.warn(message)
            return DisplayLayoutRestoreResult(
                appliedCount: 0,
                skippedCount: physicalSnapshotEntries.count,
                message: message
            )
        }

        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            throw CodexHeadlessError.displayLayout(message: "Failed to begin display layout restoration: \(beginError.rawValue).")
        }

        for match in matches {
            CGConfigureDisplayOrigin(
                config,
                CGDirectDisplayID(match.display.id),
                Int32(match.entry.originX),
                Int32(match.entry.originY)
            )
        }

        moveManagedVirtualDisplayOutOfRestoredLayout(
            config: config,
            currentDisplays: currentDisplays,
            matchedEntries: matches.map(\.entry),
            managedVirtualDisplayID: managedVirtualDisplayID
        )

        let completeError = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeError == .success else {
            throw CodexHeadlessError.displayLayout(message: "Failed to complete display layout restoration: \(completeError.rawValue).")
        }

        let skippedCount = max(0, physicalSnapshotEntries.count - matches.count)
        let message = "Restored display layout from snapshot: applied=\(matches.count), skipped=\(skippedCount)"
        logger.info("[Display] layout configuration committed applied=\(matches.count) skipped=\(skippedCount)")
        return DisplayLayoutRestoreResult(
            appliedCount: matches.count,
            skippedCount: skippedCount,
            message: message
        )
    }

    public func compactStatus(displays: [DisplayInfo]? = nil) -> String {
        let currentDisplays = displays ?? self.displays()
        return currentDisplays.map {
            "\($0.id):\($0.typeLabel):\($0.width)x\($0.height):origin=\($0.originX),\($0.originY):main=\($0.isMain):active=\($0.isActive)"
        }.joined(separator: ", ")
    }

    private func matchLayoutEntries(
        _ entries: [DisplayLayoutEntry],
        to displays: [DisplayInfo]
    ) -> [(entry: DisplayLayoutEntry, display: DisplayInfo)] {
        var usedDisplayIDs = Set<UInt32>()
        var matches: [(entry: DisplayLayoutEntry, display: DisplayInfo)] = []

        for entry in entries where entry.isActive {
            if let exactMatch = displays.first(where: { $0.id == entry.id && !usedDisplayIDs.contains($0.id) }) {
                matches.append((entry, exactMatch))
                usedDisplayIDs.insert(exactMatch.id)
                continue
            }

            if let signatureMatch = displays.first(where: { display in
                !usedDisplayIDs.contains(display.id)
                    && display.isBuiltIn == entry.isBuiltIn
                    && display.vendorNumber == entry.vendorNumber
                    && display.modelNumber == entry.modelNumber
                    && display.width == entry.width
                    && display.height == entry.height
            }) {
                matches.append((entry, signatureMatch))
                usedDisplayIDs.insert(signatureMatch.id)
            }
        }

        return matches
    }

    private func moveManagedVirtualDisplayOutOfRestoredLayout(
        config: CGDisplayConfigRef,
        currentDisplays: [DisplayInfo],
        matchedEntries: [DisplayLayoutEntry],
        managedVirtualDisplayID: UInt32?
    ) {
        guard let virtualDisplay = currentDisplays.first(where: {
            $0.id == managedVirtualDisplayID || $0.isManagedVirtual
        }) else {
            return
        }

        let maxX = matchedEntries.map { $0.originX + $0.width }.max() ?? 0
        CGConfigureDisplayOrigin(
            config,
            CGDirectDisplayID(virtualDisplay.id),
            Int32(maxX),
            0
        )
    }

    public func statusLines(managedVirtualDisplayID: UInt32? = nil) -> [String] {
        displays().map { display in
            let typeLabel = display.id == managedVirtualDisplayID ? "Managed Virtual" : display.typeLabel
            return """
              - ID: \(display.id)
                Type: \(typeLabel)
                Resolution: \(display.width)x\(display.height)
                Main: \(display.isMain ? "Yes" : "No")
                Active: \(display.isActive ? "Yes" : "No")
                Online: \(display.isOnline ? "Yes" : "No")
                Origin: \(display.originX),\(display.originY)
            """
        }
    }
}
