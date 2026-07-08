import Foundation

public struct TouchBarProbeReport {
    public var dfrDisplayLoaded: Bool
    public var dfrFoundationLoaded: Bool
    public var dfrBrightnessLoaded: Bool
    public var availableSymbols: [String]
    public var missingSymbols: [String]

    public var canAttemptHide: Bool {
        !availableSymbols.isEmpty
    }

    public var text: String {
        """
        CodexHeadless Touch Bar Probe
        -----------------------------
        DFRDisplay Loaded: \(dfrDisplayLoaded ? "Yes" : "No")
        DFRFoundation Loaded: \(dfrFoundationLoaded ? "Yes" : "No")
        DFRBrightness Loaded: \(dfrBrightnessLoaded ? "Yes" : "No")
        Candidate Symbols Available:
        \(availableSymbols.isEmpty ? "  - None" : availableSymbols.map { "  - \($0)" }.joined(separator: "\n"))
        Candidate Symbols Missing:
        \(missingSymbols.isEmpty ? "  - None" : missingSymbols.map { "  - \($0)" }.joined(separator: "\n"))

        Result: \(canAttemptHide ? "Touch Bar hide experiment can be explored behind a safety gate." : "No known Touch Bar hide symbol is available on this system.")
        """
    }
}

public struct TouchBarSafetyReport {
    public var allowed: Bool
    public var reasons: [String]
    public var warnings: [String]

    public var text: String {
        """
        CodexHeadless Touch Bar Check
        ----------------------------
        Allowed: \(allowed ? "Yes" : "No")

        Reasons:
        \(reasons.map { "  - \($0)" }.joined(separator: "\n"))

        Warnings:
        \(warnings.map { "  - \($0)" }.joined(separator: "\n"))
        """
    }
}

public final class TouchBarPrivateBridge {
    public static let shared = TouchBarPrivateBridge()

    private typealias DFRDisplaySetBrightnessFloatFunction = @convention(c) (Float) -> Void
    private typealias DFRDisplaySetBrightnessDoubleFunction = @convention(c) (Double) -> Void
    private typealias DFRDisplaySetBrightnessIntFloatFunction = @convention(c) (Int32, Float) -> Void
    private typealias DFRDisplaySetBrightnessIntDoubleFunction = @convention(c) (Int32, Double) -> Void
    private typealias DFRGetStatusInt32Function = @convention(c) () -> Int32
    private typealias DFRSetStatusInt32Function = @convention(c) (Int32) -> Void
    private typealias DFRSetStatusBoolFunction = @convention(c) (Bool) -> Void

    private let dfrDisplayHandle: UnsafeMutableRawPointer?
    private let dfrFoundationHandle: UnsafeMutableRawPointer?
    private let dfrBrightnessHandle: UnsafeMutableRawPointer?
    private let candidateSymbols = [
        "DFRDisplaySetBrightness",
        "DFRDisplayGetBrightness",
        "DFRSetStatus",
        "DFRGetStatus",
        "DFRSetStatusToString",
        "DFRSystemModalShowsCloseBoxWhenFrontMost",
        "DFRFoundationPostEvent",
        "DFRBrightnessSet"
    ]

    public init() {
        dfrDisplayHandle = Self.openFramework([
            "/System/Library/PrivateFrameworks/DFRDisplay.framework/DFRDisplay",
            "DFRDisplay.framework/DFRDisplay"
        ])
        dfrFoundationHandle = Self.openFramework([
            "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
            "DFRFoundation.framework/DFRFoundation"
        ])
        dfrBrightnessHandle = Self.openFramework([
            "/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness",
            "DFRBrightness.framework/DFRBrightness"
        ])
    }

    deinit {
        if let dfrDisplayHandle {
            dlclose(dfrDisplayHandle)
        }
        if let dfrFoundationHandle {
            dlclose(dfrFoundationHandle)
        }
        if let dfrBrightnessHandle {
            dlclose(dfrBrightnessHandle)
        }
    }

    public func probe() -> TouchBarProbeReport {
        let handles = [dfrDisplayHandle, dfrFoundationHandle, dfrBrightnessHandle]
        var available: [String] = []
        var missing: [String] = []

        for symbol in candidateSymbols {
            if Self.resolveSymbol(handles: handles, name: symbol) != nil {
                available.append(symbol)
            } else {
                missing.append(symbol)
            }
        }

        return TouchBarProbeReport(
            dfrDisplayLoaded: dfrDisplayHandle != nil,
            dfrFoundationLoaded: dfrFoundationHandle != nil,
            dfrBrightnessLoaded: dfrBrightnessHandle != nil,
            availableSymbols: available,
            missingSymbols: missing
        )
    }

    public func check(config: AppConfig) -> TouchBarSafetyReport {
        let probe = probe()
        var allowed = true
        var reasons: [String] = []
        var warnings: [String] = []

        if config.hideTouchBarInHeadless == true {
            reasons.append("Experimental Touch Bar hide config is enabled.")
        } else {
            allowed = false
            reasons.append("Experimental Touch Bar hide config is disabled.")
        }

        if probe.dfrDisplayLoaded || probe.dfrFoundationLoaded || probe.dfrBrightnessLoaded {
            reasons.append("At least one DFR private framework is loadable.")
        } else {
            allowed = false
            reasons.append("No DFR private framework could be loaded.")
        }

        if probe.canAttemptHide {
            reasons.append("At least one candidate Touch Bar private symbol is available.")
        } else {
            allowed = false
            reasons.append("No known Touch Bar hide candidate symbol is available.")
        }

        warnings.append("Touch Bar hiding uses private macOS APIs and may break after macOS updates.")
        warnings.append("Hide My Bar's public README confirms this class of feature relies on private APIs.")
        warnings.append("The v0.5 default hide path clears Control Strip UI via defaults and restores it from backup on `off`.")

        return TouchBarSafetyReport(allowed: allowed, reasons: reasons, warnings: warnings)
    }

    public func setHidden(action: TouchBarExperimentAction, variant: TouchBarExperimentVariant) -> String? {
        let brightness: Double = action == .hide ? 0 : 1
        switch variant {
        case .dfrDisplayBrightnessFloat:
            return setBrightnessFloat(Float(brightness))
        case .dfrDisplayBrightnessDouble:
            return setBrightnessDouble(brightness)
        case .dfrDisplayBrightnessIntFloat:
            return setBrightnessIntFloat(displayID: 0, brightness: Float(brightness))
        case .dfrDisplayBrightnessIntDouble:
            return setBrightnessIntDouble(displayID: 0, brightness: brightness)
        case .dfrGetStatusInt32:
            return getStatusInt32()
        case .dfrSetStatusInt32:
            return setStatusInt32(action == .hide ? 0 : 1)
        case .dfrSetStatusInt32Value2:
            return setStatusInt32(action == .hide ? 2 : 1)
        case .dfrSetStatusInt32Value3:
            return setStatusInt32(action == .hide ? 3 : 1)
        case .dfrSetStatusBool:
            return setStatusBool(action == .show)
        case .defaultsPresentationFunctionKeys:
            return setPresentationMode(action == .hide ? "functionKeys" : "fullControlStrip")
        case .defaultsPresentationAppWithControlStrip:
            return setPresentationMode(action == .hide ? "appWithControlStrip" : "fullControlStrip")
        case .defaultsPresentationFullControlStrip:
            return setPresentationMode("fullControlStrip")
        case .defaultsControlStripEmpty:
            return action == .hide ? emptyControlStrip() : restoreControlStripBackup()
        }
    }

    private func setBrightnessFloat(_ brightness: Float) -> String? {
        guard let symbol = Self.resolveSymbol(
            handles: [dfrDisplayHandle, dfrFoundationHandle, dfrBrightnessHandle],
            name: "DFRDisplaySetBrightness"
        ) else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: DFRDisplaySetBrightnessFloatFunction.self)
        function(brightness)
        return "DFRDisplaySetBrightness/float"
    }

    private func setBrightnessDouble(_ brightness: Double) -> String? {
        guard let symbol = Self.resolveSymbol(
            handles: [dfrDisplayHandle, dfrFoundationHandle, dfrBrightnessHandle],
            name: "DFRDisplaySetBrightness"
        ) else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: DFRDisplaySetBrightnessDoubleFunction.self)
        function(brightness)
        return "DFRDisplaySetBrightness/double"
    }

    private func setBrightnessIntFloat(displayID: Int32, brightness: Float) -> String? {
        guard let symbol = Self.resolveSymbol(
            handles: [dfrDisplayHandle, dfrFoundationHandle, dfrBrightnessHandle],
            name: "DFRDisplaySetBrightness"
        ) else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: DFRDisplaySetBrightnessIntFloatFunction.self)
        function(displayID, brightness)
        return "DFRDisplaySetBrightness/int-float display=\(displayID) brightness=\(brightness)"
    }

    private func setBrightnessIntDouble(displayID: Int32, brightness: Double) -> String? {
        guard let symbol = Self.resolveSymbol(
            handles: [dfrDisplayHandle, dfrFoundationHandle, dfrBrightnessHandle],
            name: "DFRDisplaySetBrightness"
        ) else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: DFRDisplaySetBrightnessIntDoubleFunction.self)
        function(displayID, brightness)
        return "DFRDisplaySetBrightness/int-double display=\(displayID) brightness=\(brightness)"
    }

    private func getStatusInt32() -> String? {
        guard let symbol = Self.resolveSymbol(
            handles: [dfrDisplayHandle, dfrFoundationHandle, dfrBrightnessHandle],
            name: "DFRGetStatus"
        ) else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: DFRGetStatusInt32Function.self)
        let status = function()
        return "DFRGetStatus/int32=\(status)"
    }

    private func setStatusInt32(_ status: Int32) -> String? {
        guard let symbol = Self.resolveSymbol(
            handles: [dfrDisplayHandle, dfrFoundationHandle, dfrBrightnessHandle],
            name: "DFRSetStatus"
        ) else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: DFRSetStatusInt32Function.self)
        function(status)
        return "DFRSetStatus/int32=\(status)"
    }

    private func setStatusBool(_ enabled: Bool) -> String? {
        guard let symbol = Self.resolveSymbol(
            handles: [dfrDisplayHandle, dfrFoundationHandle, dfrBrightnessHandle],
            name: "DFRSetStatus"
        ) else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: DFRSetStatusBoolFunction.self)
        function(enabled)
        return "DFRSetStatus/bool=\(enabled)"
    }

    private func setPresentationMode(_ mode: String) -> String? {
        do {
            let writeResult = try Shell.run(
                "/usr/bin/defaults",
                ["write", "com.apple.touchbar.agent", "PresentationModeGlobal", mode]
            )
            guard writeResult.succeeded else {
                return nil
            }

            restartTouchBarAgents()
            return "defaults PresentationModeGlobal=\(mode)"
        } catch {
            return nil
        }
    }

    private func restartTouchBarAgents() {
        _ = try? Shell.run("/usr/bin/killall", ["ControlStrip"])
        _ = try? Shell.run("/usr/bin/killall", ["TouchBarServer"])
        _ = try? Shell.run("/usr/bin/killall", ["TouchBarAgent"])
    }

    private func emptyControlStrip() -> String? {
        do {
            try CodexHeadlessPaths.ensureDirectories()
            let backupURL = CodexHeadlessPaths.touchBarControlStripBackupFile
            let backupAlreadyExists = FileManager.default.fileExists(atPath: backupURL.path)
            if !backupAlreadyExists {
                let exportResult = try Shell.run(
                    "/usr/bin/defaults",
                    ["export", "com.apple.controlstrip", backupURL.path]
                )
                guard exportResult.succeeded else {
                    return nil
                }
            }

            let writeResult = try Shell.run(
                "/usr/bin/defaults",
                ["write", "com.apple.controlstrip", "FullCustomized", "-array"]
            )
            guard writeResult.succeeded else {
                return nil
            }

            _ = setPresentationMode("fullControlStrip")
            restartTouchBarAgents()
            let backupText = backupAlreadyExists ? "existing-backup" : "new-backup"
            return "defaults controlstrip FullCustomized=empty \(backupText)=\(backupURL.path)"
        } catch {
            return nil
        }
    }

    private func restoreControlStripBackup() -> String? {
        do {
            let backupURL = CodexHeadlessPaths.touchBarControlStripBackupFile
            guard FileManager.default.fileExists(atPath: backupURL.path) else {
                _ = setPresentationMode("fullControlStrip")
                return "defaults controlstrip backup missing; restored PresentationModeGlobal=fullControlStrip"
            }

            let importResult = try Shell.run(
                "/usr/bin/defaults",
                ["import", "com.apple.controlstrip", backupURL.path]
            )
            guard importResult.succeeded else {
                return nil
            }

            _ = setPresentationMode("fullControlStrip")
            restartTouchBarAgents()
            return "defaults controlstrip restored backup=\(backupURL.path)"
        } catch {
            return nil
        }
    }

    private static func openFramework(_ candidates: [String]) -> UnsafeMutableRawPointer? {
        for candidate in candidates {
            if let handle = dlopen(candidate, RTLD_LAZY) {
                return handle
            }
        }
        return nil
    }

    private static func resolveSymbol(handles: [UnsafeMutableRawPointer?], name: String) -> UnsafeMutableRawPointer? {
        for handle in handles {
            guard let handle else {
                continue
            }
            if let symbol = dlsym(handle, name) {
                return symbol
            }
        }
        return nil
    }
}
