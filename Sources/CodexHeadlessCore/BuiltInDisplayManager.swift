import Foundation

public struct BrightnessCapability: Equatable {
    public var available: Bool
    public var method: String?
    public var guidance: String
}

public struct BrightnessChangeResult {
    public var success: Bool
    public var method: String
    public var message: String

    public static func succeeded(method: String, message: String) -> BrightnessChangeResult {
        BrightnessChangeResult(success: true, method: method, message: message)
    }

    public static func failed(_ message: String) -> BrightnessChangeResult {
        BrightnessChangeResult(success: false, method: "none", message: message)
    }
}

public struct SoftDisconnectResult {
    public var success: Bool
    public var method: String
    public var message: String
    public var crashed: Bool

    public static func succeeded(method: String, message: String) -> SoftDisconnectResult {
        SoftDisconnectResult(success: true, method: method, message: message, crashed: false)
    }

    public static func failed(_ message: String) -> SoftDisconnectResult {
        SoftDisconnectResult(success: false, method: "none", message: message, crashed: false)
    }

    public static func crashed(_ message: String) -> SoftDisconnectResult {
        SoftDisconnectResult(success: false, method: "none", message: message, crashed: true)
    }
}

public final class BuiltInDisplayManager {
    private let logger: CHLogger
    private let coreDisplayBridge: CoreDisplayPrivateBridge
    private let recoveryJournalStore: RecoveryJournalStoring
    private let capabilityStore: HelperCapabilityStore

    public init(
        logger: CHLogger = CHLogger(),
        coreDisplayBridge: CoreDisplayPrivateBridge = .shared,
        recoveryJournalStore: RecoveryJournalStoring = RecoveryJournalStore(),
        capabilityStore: HelperCapabilityStore? = nil
    ) {
        self.logger = logger
        self.coreDisplayBridge = coreDisplayBridge
        self.recoveryJournalStore = recoveryJournalStore
        self.capabilityStore = capabilityStore ?? HelperCapabilityStore(journalStore: recoveryJournalStore)
    }

    public func currentBrightness() -> Float? {
        // IODisplayConnect does not expose a reliable CoreGraphics display-ID
        // mapping on all supported macOS versions. Do not read an arbitrary
        // external display and record it as the built-in brightness.
        return nil
    }

    public func brightnessCapability() -> BrightnessCapability {
        return BrightnessCapability(
            available: false,
            method: nil,
            guidance: "Reliable built-in brightness readback is unavailable. CodexHeadless will not use an irreversible keyboard-brightness fallback."
        )
    }

    public func dimBuiltInDisplay() -> BrightnessChangeResult {
        .failed("Brightness fallback is disabled because the original built-in brightness cannot be read and restored with verified readback.")
    }

    @discardableResult
    public func restoreBrightness(_ brightness: Float?) -> BrightnessChangeResult {
        guard let brightness else {
            return .failed("Original built-in brightness was unknown. Adjust brightness manually if needed; CodexHeadless did not apply a guessed value.")
        }
        _ = brightness
        return .failed("Verified built-in brightness restore is unavailable. Replacement display and Keep Awake must remain active until the display is made visible manually.")
    }

    public func attemptSoftDisconnectIfSafe(
        builtInDisplayID: UInt32?,
        hasAlternativeDisplay: Bool,
        enabled: Bool
    ) -> SoftDisconnectResult {
        guard hasAlternativeDisplay else {
            logger.warn("Skipping built-in display soft-disconnect because no alternative display is active.")
            return .failed("No alternative display is active.")
        }

        guard enabled else {
            logger.info("Experimental built-in display soft-disconnect is disabled; irreversible brightness fallback is unavailable.")
            return .failed("Soft-disconnect is disabled.")
        }

        guard let builtInDisplayID else {
            logger.warn("Skipping built-in display soft-disconnect because built-in display ID is unknown.")
            return .failed("Built-in display ID is unknown.")
        }

        let probe = coreDisplayBridge.probe()
        let skyLightReady = probe.mainConnectionAvailable && probe.configureDisplayEnabledAvailable
        guard probe.setUserDisabledAvailable || skyLightReady else {
            logger.warn("CoreDisplay/SkyLight soft-disconnect symbols are unavailable; irreversible brightness fallback is disabled.")
            return .failed("CoreDisplay/SkyLight soft-disconnect symbols are unavailable.")
        }

        if let helperResult = runSoftDisconnectHelper(displayID: builtInDisplayID, disabled: true) {
            if helperResult.success {
                logger.info("[Helper] built-in-disable displayID=\(builtInDisplayID) method=\(helperResult.method) result=success")
                return helperResult
            }

            logger.warn(helperResult.message)
            return helperResult
        }

        logger.warn("No codex-headless helper executable was available for isolated soft-disconnect; irreversible brightness fallback is disabled.")
        return .failed("No codex-headless helper executable was available for isolated soft-disconnect.")
    }

    @discardableResult
    public func restoreBuiltInDisplay(displayID: UInt32?) -> SoftDisconnectResult {
        guard let displayID else {
            logger.info("Built-in display restore requested without a stored display ID.")
            return .failed("No stored built-in display ID to restore.")
        }

        let probe = coreDisplayBridge.probe()
        let skyLightReady = probe.mainConnectionAvailable && probe.configureDisplayEnabledAvailable
        guard probe.setUserDisabledAvailable || skyLightReady else {
            logger.warn("CoreDisplay/SkyLight restore symbols are unavailable.")
            return .failed("CoreDisplay/SkyLight restore symbols are unavailable.")
        }

        if let helperResult = runSoftDisconnectHelper(displayID: displayID, disabled: false) {
            if helperResult.success {
                logger.info("[Helper] built-in-enable displayID=\(displayID) method=\(helperResult.method) result=success")
                return helperResult
            }

            logger.warn(helperResult.message)
            return helperResult
        }

        logger.warn("No codex-headless helper executable was available for isolated built-in restore.")
        return .failed("No codex-headless helper executable was available for isolated built-in restore.")
    }

    private func runSoftDisconnectHelper(displayID: UInt32, disabled: Bool) -> SoftDisconnectResult? {
        guard let helperPath = helperExecutablePath() else {
            return nil
        }

        let action = disabled ? "disable" : "enable"
        do {
            let operationID = (try recoveryJournalStore.read()?.operationID)
                ?? "standalone-soft-disconnect-\(UUID().uuidString.lowercased())"
            let capability = try capabilityStore.reserve(
                kind: .softDisconnectApply,
                operationID: operationID,
                expectedExecutablePath: helperPath
            )
            let result = try Shell.run(helperPath, [
                "internal-helper",
                InternalHelperKind.softDisconnectApply.rawValue,
                capability.capabilityID,
                capability.nonce,
                capability.operationID,
                String(displayID),
                action,
                "default"
            ], timeoutSeconds: 5)
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let errorOutput = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.succeeded {
                let method = output.isEmpty ? "private-helper" : output
                let verb = disabled ? "soft-disconnected" : "restored"
                return .succeeded(
                    method: method,
                    message: "Built-in display \(displayID) \(verb) via isolated helper (\(method))."
                )
            }

            let detail = errorOutput.isEmpty
                ? "\(result.terminationDescription), code \(result.exitCode)"
                : errorOutput
            let message = "Isolated soft-disconnect helper failed for display \(displayID): \(detail)"
            if result.wasUncaughtSignal(11) || result.exitCode == 11 {
                return .crashed("\(message). Soft-disconnect has been disabled because the private API helper crashed with SIGSEGV.")
            }
            return .failed(message)
        } catch {
            return .failed("Unable to run isolated soft-disconnect helper: \(error.localizedDescription)")
        }
    }

    private func helperExecutablePath() -> String? {
        HelperExecutableResolver.resolveCodexHeadless()
    }
}
