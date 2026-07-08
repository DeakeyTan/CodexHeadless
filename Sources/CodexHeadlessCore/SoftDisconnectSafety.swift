import Foundation

public struct SoftDisconnectSafetyReport {
    public var allowed: Bool
    public var reasons: [String]
    public var warnings: [String]

    public var text: String {
        """
        CodexHeadless Soft-Disconnect Check
        -----------------------------------
        Allowed: \(allowed ? "Yes" : "No")

        Reasons:
        \(reasons.map { "  - \($0)" }.joined(separator: "\n"))

        Warnings:
        \(warnings.isEmpty ? "  - None" : warnings.map { "  - \($0)" }.joined(separator: "\n"))
        """
    }
}

public final class SoftDisconnectSafety {
    private let configManager: ConfigManager
    private let displayManager: DisplayManager

    public init(
        configManager: ConfigManager = ConfigManager(),
        displayManager: DisplayManager = DisplayManager()
    ) {
        self.configManager = configManager
        self.displayManager = displayManager
    }

    public func check() -> SoftDisconnectSafetyReport {
        let config = configManager.load()
        let displays = displayManager.displays()
        let builtIn = displays.first { $0.isBuiltIn }
        let external = displays.first { !$0.isBuiltIn && $0.isActive && $0.isOnline }
        let main = displays.first { $0.isMain }

        var allowed = true
        var reasons: [String] = []
        var warnings: [String] = []

        if config.softDisconnectBuiltInDisplay == true {
            reasons.append("Experimental soft-disconnect config is enabled.")
        } else {
            allowed = false
            reasons.append("Experimental soft-disconnect config is disabled.")
        }

        if let blockedReason = config.softDisconnectBlockedReason, !blockedReason.isEmpty {
            allowed = false
            reasons.append("Experimental soft-disconnect is blocked: \(blockedReason)")
        }

        if builtIn != nil {
            reasons.append("Built-in display is detected.")
        } else {
            allowed = false
            reasons.append("Built-in display is not detected.")
        }

        if let external {
            reasons.append("Alternative display is active: ID \(external.id), \(external.width)x\(external.height).")
        } else {
            allowed = false
            reasons.append("No active external / Dummy display detected.")
        }

        if main?.isBuiltIn == true {
            allowed = false
            reasons.append("Built-in display is still the main display.")
        } else if main != nil {
            reasons.append("Main display is not built-in.")
        } else {
            allowed = false
            reasons.append("Main display is unknown.")
        }

        let probe = CoreDisplayPrivateBridge.shared.probe()
        let skyLightReady = probe.mainConnectionAvailable && probe.configureDisplayEnabledAvailable
        if probe.setUserDisabledAvailable || skyLightReady {
            let method = probe.setUserDisabledAvailable ? "CoreDisplay user-disabled" : "SkyLight display-enabled"
            reasons.append("\(method) soft-disconnect symbol is available.")
        } else {
            allowed = false
            reasons.append("CoreDisplay/SkyLight soft-disconnect symbols are unavailable.")
        }

        warnings.append("This check does not disconnect any display.")
        warnings.append("Soft-disconnect uses a private macOS API and may break after macOS updates.")
        warnings.append("Keep SSH access ready before any future soft-disconnect experiment.")

        return SoftDisconnectSafetyReport(allowed: allowed, reasons: reasons, warnings: warnings)
    }
}
