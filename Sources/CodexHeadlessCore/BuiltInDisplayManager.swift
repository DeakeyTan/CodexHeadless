import Foundation
import IOKit
import IOKit.graphics

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

    public init(
        logger: CHLogger = CHLogger(),
        coreDisplayBridge: CoreDisplayPrivateBridge = .shared
    ) {
        self.logger = logger
        self.coreDisplayBridge = coreDisplayBridge
    }

    public func currentBrightness() -> Float? {
        var serviceIterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &serviceIterator)
        guard result == KERN_SUCCESS else {
            logger.warn("Unable to query display services for brightness.")
            return nil
        }
        defer { IOObjectRelease(serviceIterator) }

        var service = IOIteratorNext(serviceIterator)
        while service != 0 {
            defer { service = IOIteratorNext(serviceIterator) }
            var brightness: Float = 0
            let err = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
            IOObjectRelease(service)
            if err == KERN_SUCCESS {
                return brightness
            }
        }

        return nil
    }

    @discardableResult
    public func setBrightness(_ brightness: Float) -> Bool {
        setBrightnessUsingIOKit(brightness)
    }

    public func dimBuiltInDisplay() -> BrightnessChangeResult {
        let target: Float = 0

        if setBrightnessUsingIOKit(target) {
            return .succeeded(method: "iokit", message: "Built-in display brightness set to 0 via IOKit.")
        }

        if setBrightnessUsingBrightnessTool(target) {
            return .succeeded(method: "brightness-tool", message: "Built-in display brightness set to 0 via brightness command.")
        }

        if pressBrightnessKey(keyCode: 145, repeatCount: 32, label: "brightness down") {
            return .succeeded(method: "applescript-keycode", message: "Brightness down key sent via AppleScript fallback.")
        }

        return .failed("Built-in display brightness fallback failed. IOKit, brightness command, and AppleScript key events were unavailable.")
    }

    @discardableResult
    public func restoreBrightness(_ brightness: Float?) -> BrightnessChangeResult {
        let target = max(0.1, min(1, brightness ?? 0.7))

        if setBrightnessUsingIOKit(target) {
            return .succeeded(method: "iokit", message: "Built-in display brightness restored via IOKit.")
        }

        if setBrightnessUsingBrightnessTool(target) {
            return .succeeded(method: "brightness-tool", message: "Built-in display brightness restored via brightness command.")
        }

        let steps = max(4, min(16, Int((target * 16).rounded())))
        if pressBrightnessKey(keyCode: 144, repeatCount: steps, label: "brightness up") {
            return .succeeded(method: "applescript-keycode", message: "Brightness up key sent via AppleScript fallback.")
        }

        return .failed("Built-in display brightness restore failed. You may need to adjust brightness manually.")
    }

    private func setBrightnessUsingIOKit(_ brightness: Float) -> Bool {
        let clamped = max(0, min(1, brightness))
        var serviceIterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &serviceIterator)
        guard result == KERN_SUCCESS else {
            logger.warn("Unable to query display services to set brightness.")
            return false
        }
        defer { IOObjectRelease(serviceIterator) }

        var changed = false
        var service = IOIteratorNext(serviceIterator)
        while service != 0 {
            let err = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
            if err == KERN_SUCCESS {
                changed = true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(serviceIterator)
        }

        if changed {
            logger.info("Set built-in display brightness to \(clamped).")
        } else {
            logger.warn("No brightness-capable display service accepted brightness change.")
        }
        return changed
    }

    private func setBrightnessUsingBrightnessTool(_ brightness: Float) -> Bool {
        let clamped = max(0, min(1, brightness))
        let candidates = [
            "/opt/homebrew/bin/brightness",
            "/usr/local/bin/brightness"
        ]

        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            logger.warn("brightness command not found at /opt/homebrew/bin/brightness or /usr/local/bin/brightness.")
            return false
        }

        do {
            let value = String(format: "%.2f", clamped)
            let result = try Shell.run(executable, [value], timeoutSeconds: 2)
            if result.succeeded {
                logger.info("Set display brightness to \(value) using \(executable).")
                return true
            }

            logger.warn("brightness command failed: \(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            return false
        } catch {
            logger.warn("Unable to run brightness command: \(error.localizedDescription)")
            return false
        }
    }

    private func pressBrightnessKey(keyCode: Int, repeatCount: Int, label: String) -> Bool {
        let script = """
        tell application "System Events"
          repeat \(repeatCount) times
            key code \(keyCode)
            delay 0.02
          end repeat
        end tell
        """

        do {
            let result = try Shell.run("/usr/bin/osascript", ["-e", script], timeoutSeconds: 4)
            if result.succeeded {
                logger.info("Sent \(repeatCount) \(label) key events via AppleScript.")
                return true
            }

            let detail = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.warn("AppleScript \(label) fallback failed: \(detail)")
            return false
        } catch {
            logger.warn("Unable to run AppleScript \(label) fallback: \(error.localizedDescription)")
            return false
        }
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
            logger.info("Experimental built-in display soft-disconnect is disabled; using brightness fallback.")
            return .failed("Soft-disconnect is disabled.")
        }

        guard let builtInDisplayID else {
            logger.warn("Skipping built-in display soft-disconnect because built-in display ID is unknown.")
            return .failed("Built-in display ID is unknown.")
        }

        let probe = coreDisplayBridge.probe()
        let skyLightReady = probe.mainConnectionAvailable && probe.configureDisplayEnabledAvailable
        guard probe.setUserDisabledAvailable || skyLightReady else {
            logger.warn("CoreDisplay/SkyLight soft-disconnect symbols are unavailable; using brightness fallback.")
            return .failed("CoreDisplay/SkyLight soft-disconnect symbols are unavailable.")
        }

        if let helperResult = runSoftDisconnectHelper(displayID: builtInDisplayID, disabled: true) {
            if helperResult.success {
                logger.info(helperResult.message)
                return helperResult
            }

            logger.warn(helperResult.message)
            return helperResult
        }

        logger.warn("No codex-headless helper executable was available for isolated soft-disconnect; using brightness fallback.")
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
                logger.info(helperResult.message)
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
            let result = try Shell.run(helperPath, ["__soft-disconnect-apply", String(displayID), action], timeoutSeconds: 5)
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
