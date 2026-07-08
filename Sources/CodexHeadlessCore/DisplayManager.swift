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

public final class DisplayManager {
    private let logger: CHLogger

    public init(logger: CHLogger = CHLogger()) {
        self.logger = logger
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
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let present = displays().contains { $0.id == id }
            if present == expectedPresent {
                return true
            }
            Thread.sleep(forTimeInterval: 0.15)
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
        let currentDisplays = displays().filter { $0.isActive }
        guard !currentDisplays.isEmpty else {
            logger.warn("No active displays available while restoring main display priority.")
            return
        }

        let target = currentDisplays.first {
            !$0.isBuiltIn && $0.id != managedVirtualDisplayID && !$0.isManagedVirtual
        } ?? currentDisplays.first {
            $0.isBuiltIn
        } ?? currentDisplays.first {
            $0.id != managedVirtualDisplayID
        } ?? currentDisplays[0]

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
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let display = restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID) {
                return display
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return restorePriorityDisplay(managedVirtualDisplayID: managedVirtualDisplayID)
    }

    public func setMainDisplay(id targetID: UInt32, reason: String = "requested display") throws -> Bool {
        guard let target = display(id: targetID),
              target.isActive,
              target.isBuiltIn || target.isOnline || target.isManagedVirtual else {
            logger.warn("Display \(targetID) is not an active external/dummy/virtual display.")
            return false
        }

        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            throw NSError(domain: "CodexHeadless.Display", code: Int(beginError.rawValue), userInfo: [
                NSLocalizedDescriptionKey: "Failed to begin display configuration."
            ])
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
            throw NSError(domain: "CodexHeadless.Display", code: Int(completeError.rawValue), userInfo: [
                NSLocalizedDescriptionKey: "Failed to complete display configuration."
            ])
        }

        logger.info("Set \(reason) as main display: \(target.id)")
        return true
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
