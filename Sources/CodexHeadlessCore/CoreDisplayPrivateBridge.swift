import CoreGraphics
import Foundation

public struct CoreDisplayProbeReport {
    public var frameworkLoaded: Bool
    public var setUserDisabledAvailable: Bool
    public var isUserDisabledAvailable: Bool
    public var setUserDisabledSymbolName: String?
    public var isUserDisabledSymbolName: String?
    public var skyLightLoaded: Bool
    public var mainConnectionAvailable: Bool
    public var configureDisplayEnabledAvailable: Bool
    public var mainConnectionSymbolName: String?
    public var configureDisplayEnabledSymbolName: String?

    public var text: String {
        """
        CodexHeadless CoreDisplay Probe
        -------------------------------
        CoreDisplay Loaded: \(frameworkLoaded ? "Yes" : "No")
        Set User Disabled Symbol: \(setUserDisabledAvailable ? "Available (\(setUserDisabledSymbolName ?? "unknown"))" : "Missing")
        Is User Disabled Symbol: \(isUserDisabledAvailable ? "Available (\(isUserDisabledSymbolName ?? "unknown"))" : "Missing")
        SkyLight Loaded: \(skyLightLoaded ? "Yes" : "No")
        Main Connection Symbol: \(mainConnectionAvailable ? "Available (\(mainConnectionSymbolName ?? "unknown"))" : "Missing")
        Configure Display Enabled Symbol: \(configureDisplayEnabledAvailable ? "Available (\(configureDisplayEnabledSymbolName ?? "unknown"))" : "Missing")

        Result: \(setUserDisabledAvailable || (mainConnectionAvailable && configureDisplayEnabledAvailable) ? "Soft-disconnect attempt can be tried behind the safety gate." : "Soft-disconnect private symbols are unavailable on this system.")
        """
    }
}

public final class CoreDisplayPrivateBridge {
    public static let shared = CoreDisplayPrivateBridge()

    private typealias SetUserDisabledFunction = @convention(c) (UInt32, Bool) -> Int32
    private typealias IsUserDisabledFunction = @convention(c) (UInt32) -> Bool
    private typealias MainConnectionIDFunction = @convention(c) () -> UInt32
    private typealias ConfigureDisplayEnabledV1Function = @convention(c) (UInt32, CGDisplayConfigRef, UInt32, Bool) -> Int32
    private typealias ConfigureDisplayEnabledV2Function = @convention(c) (UInt32, UInt32, Bool) -> Int32
    private typealias ConfigureDisplayEnabledV3Function = @convention(c) (CGDisplayConfigRef, UInt32, Bool) -> Int32
    private typealias ConfigureDisplayEnabledV4Function = @convention(c) (UInt32, CGDisplayConfigRef, UInt32, Bool, UInt32) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let skyLightHandle: UnsafeMutableRawPointer?
    private let setUserDisabledFunction: SetUserDisabledFunction?
    private let isUserDisabledFunction: IsUserDisabledFunction?
    private let mainConnectionIDFunction: MainConnectionIDFunction?
    private let configureDisplayEnabledSymbol: UnsafeMutableRawPointer?
    private let setUserDisabledSymbolName: String?
    private let isUserDisabledSymbolName: String?
    private let mainConnectionSymbolName: String?
    private let configureDisplayEnabledSymbolName: String?

    public init() {
        let candidates = [
            "/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay",
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            "CoreDisplay.framework/CoreDisplay"
        ]

        var loadedHandle: UnsafeMutableRawPointer?
        for candidate in candidates {
            loadedHandle = dlopen(candidate, RTLD_LAZY)
            if loadedHandle != nil {
                break
            }
        }

        handle = loadedHandle

        let skyLightCandidates = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "SkyLight.framework/SkyLight"
        ]

        var loadedSkyLightHandle: UnsafeMutableRawPointer?
        for candidate in skyLightCandidates {
            loadedSkyLightHandle = dlopen(candidate, RTLD_LAZY)
            if loadedSkyLightHandle != nil {
                break
            }
        }

        skyLightHandle = loadedSkyLightHandle

        let setCandidates = [
            "CoreDisplay_Display_SetUserDisabled",
            "CoreDisplay_Display_SetIsUserDisabled",
            "CoreDisplay_Display_SetDisabled"
        ]

        if let resolved = Self.resolveSymbol(handle: loadedHandle, candidates: setCandidates) {
            setUserDisabledFunction = unsafeBitCast(resolved.symbol, to: SetUserDisabledFunction.self)
            setUserDisabledSymbolName = resolved.name
        } else {
            setUserDisabledFunction = nil
            setUserDisabledSymbolName = nil
        }

        let isCandidates = [
            "CoreDisplay_Display_IsUserDisabled",
            "CoreDisplay_Display_GetUserDisabled",
            "CoreDisplay_Display_IsDisabled"
        ]

        if let resolved = Self.resolveSymbol(handle: loadedHandle, candidates: isCandidates) {
            isUserDisabledFunction = unsafeBitCast(resolved.symbol, to: IsUserDisabledFunction.self)
            isUserDisabledSymbolName = resolved.name
        } else {
            isUserDisabledFunction = nil
            isUserDisabledSymbolName = nil
        }

        let configureCandidates = [
            "CGSConfigureDisplayEnabled"
        ]

        let mainConnectionCandidates = [
            "CGSMainConnectionID",
            "SLSMainConnectionID"
        ]

        if let resolved = Self.resolveSymbol(handle: loadedSkyLightHandle, candidates: mainConnectionCandidates) {
            mainConnectionIDFunction = unsafeBitCast(resolved.symbol, to: MainConnectionIDFunction.self)
            mainConnectionSymbolName = resolved.name
        } else {
            mainConnectionIDFunction = nil
            mainConnectionSymbolName = nil
        }

        if let resolved = Self.resolveSymbol(handle: loadedSkyLightHandle, candidates: configureCandidates) {
            configureDisplayEnabledSymbol = resolved.symbol
            configureDisplayEnabledSymbolName = resolved.name
        } else {
            configureDisplayEnabledSymbol = nil
            configureDisplayEnabledSymbolName = nil
        }
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
        if let skyLightHandle {
            dlclose(skyLightHandle)
        }
    }

    public func probe() -> CoreDisplayProbeReport {
        CoreDisplayProbeReport(
            frameworkLoaded: handle != nil,
            setUserDisabledAvailable: setUserDisabledFunction != nil,
            isUserDisabledAvailable: isUserDisabledFunction != nil,
            setUserDisabledSymbolName: setUserDisabledSymbolName,
            isUserDisabledSymbolName: isUserDisabledSymbolName,
            skyLightLoaded: skyLightHandle != nil,
            mainConnectionAvailable: mainConnectionIDFunction != nil,
            configureDisplayEnabledAvailable: configureDisplayEnabledSymbol != nil,
            mainConnectionSymbolName: mainConnectionSymbolName,
            configureDisplayEnabledSymbolName: configureDisplayEnabledSymbolName
        )
    }

    public func setUserDisabled(displayID: UInt32, disabled: Bool) -> Bool {
        setUserDisabledMethod(displayID: displayID, disabled: disabled) != nil
    }

    public func setUserDisabledMethod(displayID: UInt32, disabled: Bool) -> String? {
        if let setUserDisabledFunction {
            return setUserDisabledFunction(displayID, disabled) == 0 ? (setUserDisabledSymbolName ?? "CoreDisplay_Display_SetUserDisabled") : nil
        }

        if configureDisplayEnabledSymbol != nil {
            return configureDisplayEnabled(displayID: displayID, enabled: !disabled)
                ? "\(configureDisplayEnabledSymbolName ?? "CGSConfigureDisplayEnabled")/v3"
                : nil
        }

        return nil
    }

    public func setUserDisabledMethod(
        displayID: UInt32,
        disabled: Bool,
        variant: SoftDisconnectExperimentVariant
    ) -> String? {
        switch variant {
        case .coreDisplayUserDisabled:
            guard let setUserDisabledFunction else {
                return nil
            }
            return setUserDisabledFunction(displayID, disabled) == 0
                ? (setUserDisabledSymbolName ?? variant.rawValue)
                : nil
        case .skyLightConfigureDisplayEnabledV1:
            return configureDisplayEnabledV1(displayID: displayID, enabled: !disabled)
                ? (configureDisplayEnabledSymbolName ?? variant.rawValue)
                : nil
        case .skyLightConfigureDisplayEnabledV2:
            return configureDisplayEnabledV2(displayID: displayID, enabled: !disabled)
                ? (configureDisplayEnabledSymbolName ?? variant.rawValue)
                : nil
        case .skyLightConfigureDisplayEnabledV3:
            return configureDisplayEnabledV3(displayID: displayID, enabled: !disabled)
                ? (configureDisplayEnabledSymbolName ?? variant.rawValue)
                : nil
        case .skyLightConfigureDisplayEnabledV4:
            return configureDisplayEnabledV4(displayID: displayID, enabled: !disabled)
                ? (configureDisplayEnabledSymbolName ?? variant.rawValue)
                : nil
        }
    }

    public func isUserDisabled(displayID: UInt32) -> Bool? {
        guard let isUserDisabledFunction else {
            return nil
        }

        return isUserDisabledFunction(displayID)
    }

    private func configureDisplayEnabled(displayID: UInt32, enabled: Bool) -> Bool {
        configureDisplayEnabledV3(displayID: displayID, enabled: enabled)
    }

    private func configureDisplayEnabledV1(displayID: UInt32, enabled: Bool) -> Bool {
        guard let configureDisplayEnabledSymbol,
              let mainConnectionIDFunction else {
            return false
        }

        let configureDisplayEnabledFunction = unsafeBitCast(
            configureDisplayEnabledSymbol,
            to: ConfigureDisplayEnabledV1Function.self
        )
        let connectionID = mainConnectionIDFunction()
        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            return false
        }

        let configureResult = configureDisplayEnabledFunction(connectionID, config, displayID, enabled)
        guard configureResult == 0 else {
            CGCancelDisplayConfiguration(config)
            return false
        }

        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    private func configureDisplayEnabledV2(displayID: UInt32, enabled: Bool) -> Bool {
        guard let configureDisplayEnabledSymbol,
              let mainConnectionIDFunction else {
            return false
        }

        let configureDisplayEnabledFunction = unsafeBitCast(
            configureDisplayEnabledSymbol,
            to: ConfigureDisplayEnabledV2Function.self
        )
        let connectionID = mainConnectionIDFunction()
        return configureDisplayEnabledFunction(connectionID, displayID, enabled) == 0
    }

    private func configureDisplayEnabledV3(displayID: UInt32, enabled: Bool) -> Bool {
        guard let configureDisplayEnabledSymbol else {
            return false
        }

        let configureDisplayEnabledFunction = unsafeBitCast(
            configureDisplayEnabledSymbol,
            to: ConfigureDisplayEnabledV3Function.self
        )
        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            return false
        }

        let configureResult = configureDisplayEnabledFunction(config, displayID, enabled)
        guard configureResult == 0 else {
            CGCancelDisplayConfiguration(config)
            return false
        }

        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    private func configureDisplayEnabledV4(displayID: UInt32, enabled: Bool) -> Bool {
        guard let configureDisplayEnabledSymbol,
              let mainConnectionIDFunction else {
            return false
        }

        let configureDisplayEnabledFunction = unsafeBitCast(
            configureDisplayEnabledSymbol,
            to: ConfigureDisplayEnabledV4Function.self
        )
        let connectionID = mainConnectionIDFunction()
        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            return false
        }

        let configureResult = configureDisplayEnabledFunction(connectionID, config, displayID, enabled, 0)
        guard configureResult == 0 else {
            CGCancelDisplayConfiguration(config)
            return false
        }

        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    private static func resolveSymbol(
        handle: UnsafeMutableRawPointer?,
        candidates: [String]
    ) -> (name: String, symbol: UnsafeMutableRawPointer)? {
        guard let handle else {
            return nil
        }

        for candidate in candidates {
            if let symbol = dlsym(handle, candidate) {
                return (candidate, symbol)
            }
        }

        return nil
    }
}
