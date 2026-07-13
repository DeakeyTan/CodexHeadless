import CodexHeadlessCore
import Foundation

func printUsage() {
    print("""
    Usage:
      codex-headless status
      codex-headless uninstall-check
      codex-headless on [--resolution WIDTHxHEIGHT] [--no-rollback]
      codex-headless off
      codex-headless confirm
      codex-headless log [--tail N]
      codex-headless layout status
      codex-headless layout backup
      codex-headless layout restore
      codex-headless layout export PATH
      codex-headless layout import PATH
      codex-headless config get resolution
      codex-headless config set resolution WIDTHxHEIGHT
      codex-headless config get scale-mode
      codex-headless config set scale-mode standard|hidpi
      codex-headless config get virtual-display-policy
      codex-headless config set virtual-display-policy auto|always|off
      codex-headless config get soft-disconnect
      codex-headless config set soft-disconnect on|off
      codex-headless config reset soft-disconnect-block
      codex-headless config get touchbar-hide
      codex-headless config set touchbar-hide on|off
      codex-headless config get hotkeys
      codex-headless config set hotkeys.enabled true|false
      codex-headless config get confirm-dialog
      codex-headless config set confirm-dialog.enabled true|false
      codex-headless config get confirmation.policy
      codex-headless config set confirmation.policy always|software-virtual-display-only|never
      codex-headless config set confirmation.timeout-seconds SECONDS
      codex-headless config get display-handoff
      codex-headless config set display-handoff.on-soft-disconnect-failure restore|brightness-fallback
      codex-headless config get timing
      codex-headless config set timing.KEY VALUE
      codex-headless config reset defaults
      codex-headless config profile safe-default|2018-intel-macbook-pro|remote-development|experimental-maximum-headless
      codex-headless config get keep-awake-backend
      codex-headless config set keep-awake-backend caffeinate|native  # native is migrated to caffeinate
      codex-headless doctor
      codex-headless self-test
      codex-headless repair --inspect-orphan-hosts
      codex-headless virtual-display probe
      codex-headless virtual-display start [--resolution WIDTHxHEIGHT] [--scale-mode standard|hidpi]
      codex-headless virtual-display stop
      codex-headless soft-disconnect check
      codex-headless soft-disconnect probe
      codex-headless soft-disconnect variants
      codex-headless soft-disconnect experiment --variant NAME --display ID --action disable|enable --i-understand-this-may-break-display-state
      codex-headless touchbar probe
      codex-headless touchbar check
      codex-headless touchbar variants
      codex-headless touchbar experiment --variant NAME --action hide|show --i-understand-this-may-affect-touchbar-state
    """)
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    fputs("\(message)\n", stderr)
    exit(code)
}

func parseBool(_ rawValue: String, usage: String) -> Bool {
    switch rawValue.lowercased() {
    case "true", "yes", "on", "1":
        return true
    case "false", "no", "off", "0":
        return false
    default:
        fail(usage)
    }
}

func fileURL(from path: String) -> URL {
    let expandedPath = (path as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expandedPath)
}

func parseSoftDisconnectExperiment(_ args: [String]) throws -> SoftDisconnectExperimentRequest {
    var variant: SoftDisconnectExperimentVariant?
    var displayID: UInt32?
    var action: SoftDisconnectExperimentAction?
    var acknowledgedRisk = false
    var index = 0

    while index < args.count {
        switch args[index] {
        case "--variant":
            guard index + 1 < args.count else {
                fail("Missing value for --variant.")
            }
            variant = SoftDisconnectExperimentVariant(rawValue: args[index + 1])
            guard variant != nil else {
                fail("Unknown variant: \(args[index + 1])")
            }
            index += 2
        case "--display":
            guard index + 1 < args.count, let parsed = UInt32(args[index + 1]) else {
                fail("Missing or invalid value for --display.")
            }
            displayID = parsed
            index += 2
        case "--action":
            guard index + 1 < args.count else {
                fail("Missing value for --action.")
            }
            action = SoftDisconnectExperimentAction(rawValue: args[index + 1])
            guard action != nil else {
                fail("Invalid --action. Use disable or enable.")
            }
            index += 2
        case "--i-understand-this-may-break-display-state":
            acknowledgedRisk = true
            index += 1
        default:
            fail("Unknown experiment option: \(args[index])")
        }
    }

    guard let variant, let displayID, let action else {
        fail("Usage: codex-headless soft-disconnect experiment --variant NAME --display ID --action disable|enable --i-understand-this-may-break-display-state")
    }

    return SoftDisconnectExperimentRequest(
        variant: variant,
        displayID: displayID,
        action: action,
        acknowledgedRisk: acknowledgedRisk
    )
}

func parseTouchBarExperiment(_ args: [String]) throws -> TouchBarExperimentRequest {
    var variant: TouchBarExperimentVariant?
    var action: TouchBarExperimentAction?
    var acknowledgedRisk = false
    var index = 0

    while index < args.count {
        switch args[index] {
        case "--variant":
            guard index + 1 < args.count else {
                fail("Missing value for --variant.")
            }
            variant = TouchBarExperimentVariant(rawValue: args[index + 1])
            guard variant != nil else {
                fail("Unknown Touch Bar variant: \(args[index + 1])")
            }
            index += 2
        case "--action":
            guard index + 1 < args.count else {
                fail("Missing value for --action.")
            }
            action = TouchBarExperimentAction(rawValue: args[index + 1])
            guard action != nil else {
                fail("Invalid --action. Use hide or show.")
            }
            index += 2
        case "--i-understand-this-may-affect-touchbar-state":
            acknowledgedRisk = true
            index += 1
        default:
            fail("Unknown Touch Bar experiment option: \(args[index])")
        }
    }

    guard let variant, let action else {
        fail("Usage: codex-headless touchbar experiment --variant NAME --action hide|show --i-understand-this-may-affect-touchbar-state")
    }

    return TouchBarExperimentRequest(
        variant: variant,
        action: action,
        acknowledgedRisk: acknowledgedRisk
    )
}
