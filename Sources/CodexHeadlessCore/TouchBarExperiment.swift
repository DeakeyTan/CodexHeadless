import Foundation

public enum TouchBarExperimentVariant: String, CaseIterable {
    case dfrDisplayBrightnessFloat = "dfr-display-brightness-float"
    case dfrDisplayBrightnessDouble = "dfr-display-brightness-double"
    case dfrDisplayBrightnessIntFloat = "dfr-display-brightness-int-float"
    case dfrDisplayBrightnessIntDouble = "dfr-display-brightness-int-double"
    case dfrGetStatusInt32 = "dfr-get-status-int32"
    case dfrSetStatusInt32 = "dfr-set-status-int32"
    case dfrSetStatusInt32Value2 = "dfr-set-status-int32-value2"
    case dfrSetStatusInt32Value3 = "dfr-set-status-int32-value3"
    case dfrSetStatusBool = "dfr-set-status-bool"
    case defaultsPresentationFunctionKeys = "defaults-presentation-function-keys"
    case defaultsPresentationAppWithControlStrip = "defaults-presentation-app-with-control-strip"
    case defaultsPresentationFullControlStrip = "defaults-presentation-full-control-strip"
    case defaultsControlStripEmpty = "defaults-control-strip-empty"
}

public enum TouchBarExperimentAction: String {
    case hide
    case show
}

public struct TouchBarExperimentRequest {
    public var variant: TouchBarExperimentVariant
    public var action: TouchBarExperimentAction
    public var acknowledgedRisk: Bool

    public init(
        variant: TouchBarExperimentVariant,
        action: TouchBarExperimentAction,
        acknowledgedRisk: Bool
    ) {
        self.variant = variant
        self.action = action
        self.acknowledgedRisk = acknowledgedRisk
    }
}

public struct TouchBarExperimentSafety {
    public var allowed: Bool
    public var reasons: [String]

    public var text: String {
        """
        Touch Bar Experiment Safety
        ---------------------------
        Allowed: \(allowed ? "Yes" : "No")
        \(reasons.map { "  - \($0)" }.joined(separator: "\n"))
        """
    }
}

public final class TouchBarExperiment {
    public init() {}

    public func safety(for request: TouchBarExperimentRequest, config: AppConfig) -> TouchBarExperimentSafety {
        let probe = TouchBarPrivateBridge.shared.probe()
        var allowed = true
        var reasons: [String] = []

        if request.acknowledgedRisk {
            reasons.append("Risk acknowledgement flag is present.")
        } else {
            allowed = false
            reasons.append("Missing --i-understand-this-may-affect-touchbar-state.")
        }

        if config.hideTouchBarInHeadless == true {
            reasons.append("Experimental Touch Bar hide config is enabled.")
        } else {
            allowed = false
            reasons.append("Experimental Touch Bar hide config is disabled.")
        }

        let requiredSymbol: String?
        switch request.variant {
        case .dfrDisplayBrightnessFloat,
             .dfrDisplayBrightnessDouble,
             .dfrDisplayBrightnessIntFloat,
             .dfrDisplayBrightnessIntDouble:
            requiredSymbol = "DFRDisplaySetBrightness"
        case .dfrGetStatusInt32:
            requiredSymbol = "DFRGetStatus"
        case .dfrSetStatusInt32,
             .dfrSetStatusInt32Value2,
             .dfrSetStatusInt32Value3,
             .dfrSetStatusBool:
            requiredSymbol = "DFRSetStatus"
        case .defaultsPresentationFunctionKeys,
             .defaultsPresentationAppWithControlStrip,
             .defaultsPresentationFullControlStrip,
             .defaultsControlStripEmpty:
            requiredSymbol = nil
        }

        if let requiredSymbol, probe.availableSymbols.contains(requiredSymbol) {
            reasons.append("\(requiredSymbol) symbol is available.")
        } else if let requiredSymbol {
            allowed = false
            reasons.append("\(requiredSymbol) symbol is missing.")
        } else {
            reasons.append("Defaults-based Touch Bar presentation experiment does not require DFR symbols.")
        }

        reasons.append("Touch Bar experiments run only in an isolated helper subprocess.")

        return TouchBarExperimentSafety(allowed: allowed, reasons: reasons)
    }
}
