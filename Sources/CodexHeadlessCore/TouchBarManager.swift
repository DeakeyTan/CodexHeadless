import Foundation

public struct TouchBarChangeResult {
    public var success: Bool
    public var method: String
    public var message: String
    public var crashed: Bool

    public static func succeeded(method: String, message: String) -> TouchBarChangeResult {
        TouchBarChangeResult(success: true, method: method, message: message, crashed: false)
    }

    public static func skipped(_ message: String) -> TouchBarChangeResult {
        TouchBarChangeResult(success: false, method: "none", message: message, crashed: false)
    }

    public static func failed(_ message: String) -> TouchBarChangeResult {
        TouchBarChangeResult(success: false, method: "none", message: message, crashed: false)
    }

    public static func crashed(_ message: String) -> TouchBarChangeResult {
        TouchBarChangeResult(success: false, method: "none", message: message, crashed: true)
    }
}

public final class TouchBarManager {
    private let logger: CHLogger
    private let bridge: TouchBarPrivateBridge

    public init(
        logger: CHLogger = CHLogger(),
        bridge: TouchBarPrivateBridge = .shared
    ) {
        self.logger = logger
        self.bridge = bridge
    }

    public func hideIfEnabled(_ enabled: Bool) -> TouchBarChangeResult {
        guard enabled else {
            return .skipped("Touch Bar hide config is disabled.")
        }

        return runHelper(action: .hide, variant: .defaultsControlStripEmpty)
    }

    public func showIfNeeded(_ wasHidden: Bool?) -> TouchBarChangeResult {
        guard wasHidden == true else {
            return .skipped("Touch Bar was not hidden by CodexHeadless.")
        }

        return runHelper(action: .show, variant: .defaultsControlStripEmpty)
    }

    private func runHelper(action: TouchBarExperimentAction, variant: TouchBarExperimentVariant) -> TouchBarChangeResult {
        guard let helperPath = HelperExecutableResolver.resolveCodexHeadless() else {
            return .failed("No codex-headless helper executable was available for isolated Touch Bar operation.")
        }

        do {
            let result = try Shell.run(helperPath, [
                "__touchbar-apply",
                action.rawValue,
                "--variant",
                variant.rawValue
            ], timeoutSeconds: 5)
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let errorOutput = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.succeeded {
                let method = output.isEmpty ? variant.rawValue : output
                let verb = action == .hide ? "UI hidden" : "UI restored"
                return .succeeded(
                    method: method,
                    message: "Touch Bar \(verb) via isolated helper (\(method))."
                )
            }

            let detail = errorOutput.isEmpty
                ? "\(result.terminationDescription), code \(result.exitCode)"
                : errorOutput
            let message = "Isolated Touch Bar helper failed: \(detail)"
            if result.wasUncaughtSignal(11) || result.exitCode == 11 {
                return .crashed("\(message).")
            }
            return .failed(message)
        } catch {
            return .failed("Unable to run isolated Touch Bar helper: \(error.localizedDescription)")
        }
    }
}
