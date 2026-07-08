import Foundation

public enum SoftDisconnectExperimentVariant: String, CaseIterable {
    case skyLightConfigureDisplayEnabledV1 = "skylight-configure-display-enabled-v1"
    case skyLightConfigureDisplayEnabledV2 = "skylight-configure-display-enabled-v2"
    case skyLightConfigureDisplayEnabledV3 = "skylight-configure-display-enabled-v3"
    case skyLightConfigureDisplayEnabledV4 = "skylight-configure-display-enabled-v4"
    case coreDisplayUserDisabled = "coredisplay-user-disabled"
}

public enum SoftDisconnectExperimentAction: String {
    case disable
    case enable
}

public struct SoftDisconnectExperimentRequest {
    public var variant: SoftDisconnectExperimentVariant
    public var displayID: UInt32
    public var action: SoftDisconnectExperimentAction
    public var acknowledgedRisk: Bool

    public init(
        variant: SoftDisconnectExperimentVariant,
        displayID: UInt32,
        action: SoftDisconnectExperimentAction,
        acknowledgedRisk: Bool
    ) {
        self.variant = variant
        self.displayID = displayID
        self.action = action
        self.acknowledgedRisk = acknowledgedRisk
    }
}

public struct SoftDisconnectExperimentSafety {
    public var allowed: Bool
    public var reasons: [String]

    public var text: String {
        """
        Experiment Safety
        -----------------
        Allowed: \(allowed ? "Yes" : "No")
        \(reasons.map { "  - \($0)" }.joined(separator: "\n"))
        """
    }
}

public final class SoftDisconnectExperiment {
    private let displayManager: DisplayManager

    public init(displayManager: DisplayManager = DisplayManager()) {
        self.displayManager = displayManager
    }

    public func safety(for request: SoftDisconnectExperimentRequest) -> SoftDisconnectExperimentSafety {
        let displays = displayManager.displays()
        let builtIn = displays.first { $0.isBuiltIn }
        let external = displays.first { !$0.isBuiltIn && $0.isActive && $0.isOnline }
        let main = displays.first { $0.isMain }
        var allowed = true
        var reasons: [String] = []

        if request.acknowledgedRisk {
            reasons.append("Risk acknowledgement flag is present.")
        } else {
            allowed = false
            reasons.append("Missing --i-understand-this-may-break-display-state.")
        }

        if request.action == .enable {
            if let builtIn {
                if builtIn.id == request.displayID {
                    reasons.append("Requested display ID \(request.displayID) is the built-in display.")
                } else {
                    reasons.append("Built-in display is detected as ID \(builtIn.id); requested ID \(request.displayID) will still be used for recovery.")
                }
            } else {
                reasons.append("Built-in display is not currently detected; enable action is allowed for recovery experiments.")
            }
            reasons.append("Enable action is allowed for recovery experiments.")
        } else {
            guard let builtIn else {
                allowed = false
                reasons.append("Built-in display is not detected.")
                return SoftDisconnectExperimentSafety(allowed: allowed, reasons: reasons)
            }

            if builtIn.id == request.displayID {
                reasons.append("Requested display ID \(request.displayID) is the built-in display.")
            } else {
                allowed = false
                reasons.append("Requested display ID \(request.displayID) is not the built-in display ID \(builtIn.id).")
            }

            if let external {
                reasons.append("Alternative display is active: ID \(external.id), \(external.width)x\(external.height).")
            } else {
                allowed = false
                reasons.append("No active external / Dummy display is available.")
            }

            if main?.isBuiltIn == true {
                allowed = false
                reasons.append("Built-in display is still main.")
            } else if main != nil {
                reasons.append("Main display is not built-in.")
            } else {
                allowed = false
                reasons.append("Main display is unknown.")
            }
        }

        return SoftDisconnectExperimentSafety(allowed: allowed, reasons: reasons)
    }
}
