import CodexHeadlessCore
import Foundation

let logger = CHLogger()
let configManager = ConfigManager(logger: logger)
let stateStore = StateStore(logger: logger)
let controller = HeadlessController(
    logger: logger,
    configManager: configManager,
    stateStore: stateStore
)

func printUsage() {
    print("""
    Usage:
      codex-headless status
      codex-headless on [--resolution WIDTHxHEIGHT] [--no-rollback]
      codex-headless off
      codex-headless confirm
      codex-headless log [--tail N]
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
      codex-headless config get keep-awake-backend
      codex-headless config set keep-awake-backend caffeinate|native
      codex-headless doctor
      codex-headless self-test
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

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    printUsage()
    exit(0)
}

do {
    switch command {
    case "__virtual-display-host":
        guard args.count == 5,
              let width = Int(args[1]),
              let height = Int(args[2]),
              let refreshRate = Int(args[3]) else {
            fail("Usage: codex-headless __virtual-display-host WIDTH HEIGHT REFRESH_RATE SCALE_MODE")
        }
        let resolution = Resolution(width: width, height: height)
        try ResolutionManager.validate(resolution)
        try VirtualDisplayHost.run(resolution: resolution, refreshRate: refreshRate, scaleMode: args[4])

    case "__touchbar-apply":
        guard args.count == 4, args[2] == "--variant" else {
            fail("Usage: codex-headless __touchbar-apply hide|show --variant NAME")
        }
        guard let action = TouchBarExperimentAction(rawValue: args[1]) else {
            fail("Usage: codex-headless __touchbar-apply hide|show --variant NAME")
        }
        guard let variant = TouchBarExperimentVariant(rawValue: args[3]) else {
            fail("Unknown Touch Bar variant: \(args[3])")
        }

        guard let method = TouchBarPrivateBridge.shared.setHidden(action: action, variant: variant) else {
            fail("Private Touch Bar call returned failure.", code: 2)
        }
        print(method)

    case "__soft-disconnect-apply":
        guard args.count >= 3, let displayID = UInt32(args[1]) else {
            fail("Usage: codex-headless __soft-disconnect-apply DISPLAY_ID disable|enable [--variant NAME]")
        }
        let action = args[2]
        guard action == "disable" || action == "enable" else {
            fail("Usage: codex-headless __soft-disconnect-apply DISPLAY_ID disable|enable [--variant NAME]")
        }

        let disabled = action == "disable"
        var variant: SoftDisconnectExperimentVariant?
        if args.count == 5, args[3] == "--variant" {
            variant = SoftDisconnectExperimentVariant(rawValue: args[4])
            guard variant != nil else {
                fail("Unknown soft-disconnect variant: \(args[4])")
            }
        } else if args.count != 3 {
            fail("Usage: codex-headless __soft-disconnect-apply DISPLAY_ID disable|enable [--variant NAME]")
        }

        let method = if let variant {
            CoreDisplayPrivateBridge.shared.setUserDisabledMethod(displayID: displayID, disabled: disabled, variant: variant)
        } else {
            CoreDisplayPrivateBridge.shared.setUserDisabledMethod(displayID: displayID, disabled: disabled)
        }

        guard let method else {
            fail("Private soft-disconnect call returned failure.", code: 2)
        }

        print(method)

    case "status":
        print(controller.statusText())

    case "on":
        var resolution: Resolution?
        var rollbackEnabled = true
        var index = 1
        while index < args.count {
            switch args[index] {
            case "--resolution":
                guard index + 1 < args.count else {
                    fail("Missing value for --resolution.")
                }
                resolution = try ResolutionManager.parse(args[index + 1])
                index += 2
            case "--no-rollback":
                rollbackEnabled = false
                index += 1
            case "--dummy-only", "--virtual", "--fallback-brightness-only":
                logger.warn("Option \(args[index]) is accepted for compatibility but not fully implemented in v0.3.")
                index += 1
            default:
                fail("Unknown option: \(args[index])")
            }
        }
        try controller.enableHeadless(resolutionOverride: resolution, rollbackEnabled: rollbackEnabled)
        print("Headless Mode requested. Run `codex-headless confirm` within the rollback window if the setup is good.")
        print("")
        print(controller.statusText())

    case "off":
        controller.restoreNormal()
        print("Normal Mode restored.")
        print("")
        print(controller.statusText())

    case "confirm":
        controller.confirm()
        print("Headless Mode confirmed.")
        print("")
        print(controller.statusText())

    case "doctor":
        let doctor = Doctor(
            configManager: configManager,
            stateStore: stateStore
        )
        print(doctor.report())

    case "self-test":
        let report = SelfTest.report()
        print(report)
        if report.contains("Result: FAIL") {
            exit(1)
        }

    case "virtual-display":
        guard args.count >= 2 else {
            fail("Usage: codex-headless virtual-display probe|start|stop")
        }
        switch args[1] {
        case "probe":
            guard args.count == 2 else {
                fail("Usage: codex-headless virtual-display probe")
            }
            print(VirtualDisplayManager().probe().text)
        case "start":
            var resolution: Resolution?
            var scaleMode: VirtualDisplayScaleMode?
            var index = 2
            while index < args.count {
                switch args[index] {
                case "--resolution":
                    guard index + 1 < args.count else {
                        fail("Missing value for --resolution.")
                    }
                    resolution = try ResolutionManager.parse(args[index + 1])
                    index += 2
                case "--scale-mode":
                    guard index + 1 < args.count else {
                        fail("Missing value for --scale-mode.")
                    }
                    scaleMode = try VirtualDisplayScaleMode.parse(args[index + 1])
                    index += 2
                default:
                    fail("Unknown virtual-display option: \(args[index])")
                }
            }
            let config = configManager.load()
            let targetResolution = resolution ?? config.virtualDisplay.resolution
            let targetScaleMode = scaleMode?.rawValue ?? config.virtualDisplay.scaleMode
            let displayID = try VirtualDisplayManager(stateStore: stateStore).createVirtualDisplay(
                resolution: targetResolution,
                refreshRate: config.virtualDisplay.refreshRate,
                scaleMode: targetScaleMode
            )
            if let displayID {
                print("virtual-display=started displayID=\(displayID) resolution=\(targetResolution) scaleMode=\(targetScaleMode)")
            } else {
                fail("virtual-display=start failed", code: 2)
            }
        case "stop":
            guard args.count == 2 else {
                fail("Usage: codex-headless virtual-display stop")
            }
            VirtualDisplayManager(stateStore: stateStore).destroyVirtualDisplayIfManaged()
            print("virtual-display=stopped")
        default:
            fail("Usage: codex-headless virtual-display probe|start|stop")
        }

    case "touchbar":
        guard args.count >= 2 else {
            fail("Usage: codex-headless touchbar probe|check|variants|experiment")
        }
        switch args[1] {
        case "probe":
            guard args.count == 2 else {
                fail("Usage: codex-headless touchbar probe")
            }
            print(TouchBarPrivateBridge.shared.probe().text)
        case "check":
            guard args.count == 2 else {
                fail("Usage: codex-headless touchbar check")
            }
            print(TouchBarPrivateBridge.shared.check(config: configManager.load()).text)
        case "variants":
            guard args.count == 2 else {
                fail("Usage: codex-headless touchbar variants")
            }
            print("""
            CodexHeadless Touch Bar Variants
            --------------------------------
            Status: research only. This command does not modify Touch Bar state.

            Candidate experiment paths:
              dfr-get-status-int32
                Shape: DFRGetStatus() -> Int32
                Intended action: read-only status probe

              dfr-display-brightness-float
                Shape: DFRDisplaySetBrightness(Float)
                Intended action: hide=0, show=1
                Result on target: SIGSEGV / signal 11

              dfr-display-brightness-double
                Shape: DFRDisplaySetBrightness(Double)
                Intended action: hide=0, show=1

              dfr-display-brightness-int-float
                Shape: DFRDisplaySetBrightness(Int32, Float)
                Intended action: display=0, hide=0, show=1
                Result on target: SIGSEGV / signal 11

              dfr-display-brightness-int-double
                Shape: DFRDisplaySetBrightness(Int32, Double)
                Intended action: display=0, hide=0, show=1
                Result on target: SIGSEGV / signal 11

              dfr-set-status-int32
                Shape: DFRSetStatus(Int32)
                Intended action: hide=0, show=1
                Result on target: API success, physical Touch Bar hide not observed

              dfr-set-status-int32-value2
                Shape: DFRSetStatus(Int32)
                Intended action: hide=2, show=1

              dfr-set-status-int32-value3
                Shape: DFRSetStatus(Int32)
                Intended action: hide=3, show=1

              dfr-set-status-bool
                Shape: DFRSetStatus(Bool)
                Intended action: hide=false, show=true

              defaults-presentation-function-keys
                Shape: defaults write com.apple.touchbar.agent PresentationModeGlobal functionKeys
                Intended action: hide=functionKeys, show=fullControlStrip

              defaults-presentation-app-with-control-strip
                Shape: defaults write com.apple.touchbar.agent PresentationModeGlobal appWithControlStrip
                Intended action: hide=appWithControlStrip, show=fullControlStrip

              defaults-presentation-full-control-strip
                Shape: defaults write com.apple.touchbar.agent PresentationModeGlobal fullControlStrip
                Intended action: restore fullControlStrip

              defaults-control-strip-empty
                Shape: defaults export com.apple.controlstrip backup; defaults write FullCustomized -array
                Intended action: hide=empty FullCustomized, show=restore backup
                Result on target: UI icons disappear, OLED black for cleared area
                Production use: default Touch Bar UI hide/show path

            Rule:
              New Touch Bar variants must be tested only via isolated helper subprocesses,
              never from the main `codex-headless on` flow.
            """)
        case "experiment":
            let request = try parseTouchBarExperiment(Array(args.dropFirst(2)))
            let safety = TouchBarExperiment().safety(for: request, config: configManager.load())
            print(safety.text)
            guard safety.allowed else {
                fail("Touch Bar experiment refused by safety gate.", code: 2)
            }

            guard let helperPath = HelperExecutableResolver.resolveCodexHeadless() else {
                fail("No codex-headless helper executable was available. Re-run install.sh or invoke the binary with an absolute path.")
            }
            let result = try Shell.run(helperPath, [
                "__touchbar-apply",
                request.action.rawValue,
                "--variant",
                request.variant.rawValue
            ])
            print("")
            print("Touch Bar Experiment Result")
            print("---------------------------")
            print("Variant: \(request.variant.rawValue)")
            print("Action: \(request.action.rawValue)")
            print("Termination: \(result.terminationDescription)")
            print("Exit Code: \(result.exitCode)")
            if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("Output: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if !result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("Error: \(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if result.wasUncaughtSignal(11) {
                print("Crash: helper terminated with SIGSEGV.")
            }
            if !result.succeeded {
                exit(result.exitCode == 0 ? 1 : result.exitCode)
            }
        default:
            fail("Usage: codex-headless touchbar probe|check|variants|experiment")
        }

    case "soft-disconnect":
        guard args.count >= 2 else {
            fail("Usage: codex-headless soft-disconnect check|probe|variants|experiment")
        }

        switch args[1] {
        case "check":
            guard args.count == 2 else {
                fail("Usage: codex-headless soft-disconnect check")
            }
            print(SoftDisconnectSafety(configManager: configManager).check().text)
        case "probe":
            guard args.count == 2 else {
                fail("Usage: codex-headless soft-disconnect probe")
            }
            print(CoreDisplayPrivateBridge.shared.probe().text)
        case "variants":
            guard args.count == 2 else {
                fail("Usage: codex-headless soft-disconnect variants")
            }
            print("""
            CodexHeadless Soft-Disconnect Variants
            --------------------------------------
            Status: research only. This command does not modify display state.

            Current implemented helper path:
              skylight-configure-display-enabled-v1
                Shape: CGSConfigureDisplayEnabled(connection, config, displayID, enabled)
                Result on target: SIGSEGV / signal 11
                Production use: disabled by circuit breaker

              skylight-configure-display-enabled-v2
                Shape: CGSConfigureDisplayEnabled(connection, displayID, enabled)
                Result on target: SIGSEGV / signal 11

            Candidate future experiment paths:

              skylight-configure-display-enabled-v3
                Shape: CGSConfigureDisplayEnabled(config, displayID, enabled)
                Result on target: success
                Production use: default soft-disconnect path

              skylight-configure-display-enabled-v4
                Shape: CGSConfigureDisplayEnabled(connection, config, displayID, enabled, flags)
                Result on target: untested; skip while v3 works

              coredisplay-user-disabled
                Shape: CoreDisplay_Display_SetUserDisabled(displayID, disabled)
                Availability on target: currently missing

            Rule:
              New variants must be tested only via isolated helper subprocesses,
              never from the main `codex-headless on` flow.
            """)
        case "experiment":
            let request = try parseSoftDisconnectExperiment(Array(args.dropFirst(2)))
            let safety = SoftDisconnectExperiment().safety(for: request)
            print(safety.text)
            guard safety.allowed else {
                fail("Experiment refused by safety gate.", code: 2)
            }

            guard let helperPath = HelperExecutableResolver.resolveCodexHeadless() else {
                fail("No codex-headless helper executable was available. Re-run install.sh or invoke the binary with an absolute path.")
            }
            let helperArgs = [
                "__soft-disconnect-apply",
                String(request.displayID),
                request.action.rawValue,
                "--variant",
                request.variant.rawValue
            ]
            let result = try Shell.run(helperPath, helperArgs)
            print("")
            print("Experiment Result")
            print("-----------------")
            print("Variant: \(request.variant.rawValue)")
            print("Display: \(request.displayID)")
            print("Action: \(request.action.rawValue)")
            print("Termination: \(result.terminationDescription)")
            print("Exit Code: \(result.exitCode)")
            if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("Output: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if !result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("Error: \(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if result.wasUncaughtSignal(11) {
                print("Crash: helper terminated with SIGSEGV.")
            } else if result.exitCode == 11 {
                print("Crash: helper exited with code 11, likely SIGSEGV on older reporting paths.")
            }
            if !result.succeeded {
                exit(result.exitCode == 0 ? 1 : result.exitCode)
            }
        default:
            fail("Usage: codex-headless soft-disconnect check|probe|variants|experiment")
        }

    case "log":
        let tailCount: Int
        if args.count == 3, args[1] == "--tail", let parsed = Int(args[2]) {
            tailCount = parsed
        } else if args.count == 1 {
            tailCount = 200
        } else {
            fail("Usage: codex-headless log [--tail N]")
        }

        let logURL = CodexHeadlessPaths.logFile
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            print("No log file yet: \(logURL.path)")
            exit(0)
        }
        let contents = try String(contentsOf: logURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        print(lines.suffix(tailCount).joined(separator: "\n"))

    case "config":
        guard args.count >= 3 else {
            fail("Usage: codex-headless config get resolution|scale-mode|virtual-display-policy|soft-disconnect|keep-awake-backend|touchbar-hide|hotkeys|confirm-dialog | config set resolution WIDTHxHEIGHT | config set scale-mode standard|hidpi | config set virtual-display-policy auto|always|off | config set soft-disconnect on|off | config set keep-awake-backend caffeinate|native | config set touchbar-hide on|off | config set hotkeys.enabled true|false | config set confirm-dialog.enabled true|false | config reset soft-disconnect-block")
        }
        let action = args[1]
        let key = args[2]
        guard key == "resolution"
            || key == "scale-mode"
            || key == "virtual-display-policy"
            || key == "soft-disconnect"
            || key == "keep-awake-backend"
            || key == "soft-disconnect-block"
            || key == "touchbar-hide"
            || key == "hotkeys"
            || key == "hotkeys.enabled"
            || key == "confirm-dialog"
            || key == "confirm-dialog.enabled" else {
            fail("Unsupported config key: \(key)")
        }

        switch action {
        case "get":
            let config = configManager.load()
            if key == "resolution" {
                print("resolution=\(config.virtualDisplay.resolution)")
            } else if key == "scale-mode" {
                print("scale-mode=\(config.virtualDisplay.scaleMode)")
            } else if key == "virtual-display-policy" {
                print("virtual-display-policy=\(VirtualDisplayPolicy.effectivePolicy(for: config.virtualDisplay).rawValue)")
            } else if key == "soft-disconnect" {
                print("soft-disconnect=\(config.softDisconnectBuiltInDisplay == true ? "on" : "off")")
            } else if key == "keep-awake-backend" {
                print("keep-awake-backend=\(config.keepAwakeBackend?.rawValue ?? KeepAwakeBackend.caffeinate.rawValue)")
            } else if key == "touchbar-hide" {
                print("touchbar-hide=\(config.hideTouchBarInHeadless == true ? "on" : "off")")
            } else if key == "hotkeys" {
                let hotkeys = config.effectiveHotkeys
                print("hotkeys.enabled=\(hotkeys.enabled)")
                print("hotkeys.enable=\(hotkeys.enable.modifiers.joined(separator: "+"))+\(hotkeys.enable.key.uppercased())")
                print("hotkeys.confirm=\(hotkeys.confirm.modifiers.joined(separator: "+"))+\(hotkeys.confirm.key.uppercased())")
                print("hotkeys.restore=\(hotkeys.restore.modifiers.joined(separator: "+"))+\(hotkeys.restore.key.uppercased())")
            } else if key == "hotkeys.enabled" {
                print("hotkeys.enabled=\(config.effectiveHotkeys.enabled)")
            } else if key == "confirm-dialog" {
                let confirmDialog = config.effectiveConfirmDialog
                print("confirm-dialog.enabled=\(confirmDialog.enabled)")
                print("confirm-dialog.timeout-seconds=\(confirmDialog.timeoutSeconds)")
                print("confirm-dialog.show-hotkey-hints=\(confirmDialog.showHotkeyHints)")
                print("confirm-dialog.show-countdown=\(confirmDialog.showCountdown)")
            } else if key == "confirm-dialog.enabled" {
                print("confirm-dialog.enabled=\(config.effectiveConfirmDialog.enabled)")
            } else {
                print("soft-disconnect-block=\(config.softDisconnectBlockedReason ?? "none")")
            }
        case "set":
            guard args.count == 4 else {
                fail("Usage: codex-headless config set resolution WIDTHxHEIGHT | config set scale-mode standard|hidpi | config set virtual-display-policy auto|always|off | config set soft-disconnect on|off | config set keep-awake-backend caffeinate|native | config set touchbar-hide on|off | config set hotkeys.enabled true|false | config set confirm-dialog.enabled true|false")
            }
            if key == "resolution" {
                let resolution = try ResolutionManager.parse(args[3])
                try configManager.setResolution(resolution)
                print("resolution=\(resolution)")
            } else if key == "scale-mode" {
                let scaleMode = try VirtualDisplayScaleMode.parse(args[3])
                try configManager.setVirtualDisplayScaleMode(scaleMode.rawValue)
                print("scale-mode=\(scaleMode.rawValue)")
            } else if key == "virtual-display-policy" {
                let policy = try VirtualDisplayPolicy.parse(args[3])
                try configManager.setVirtualDisplayPolicy(policy.rawValue)
                print("virtual-display-policy=\(policy.rawValue)")
            } else if key == "soft-disconnect" {
                let rawValue = args[3].lowercased()
                guard rawValue == "on" || rawValue == "off" else {
                    fail("Usage: codex-headless config set soft-disconnect on|off")
                }
                let enabled = rawValue == "on"
                try configManager.setSoftDisconnectBuiltInDisplay(enabled)
                print("soft-disconnect=\(enabled ? "on" : "off")")
            } else if key == "keep-awake-backend" {
                let rawValue = args[3].lowercased()
                guard let backend = KeepAwakeBackend(rawValue: rawValue) else {
                    fail("Usage: codex-headless config set keep-awake-backend caffeinate|native")
                }
                try configManager.setKeepAwakeBackend(backend)
                print("keep-awake-backend=\(backend.rawValue)")
            } else if key == "touchbar-hide" {
                let rawValue = args[3].lowercased()
                guard rawValue == "on" || rawValue == "off" else {
                    fail("Usage: codex-headless config set touchbar-hide on|off")
                }
                let enabled = rawValue == "on"
                try configManager.setHideTouchBarInHeadless(enabled)
                print("touchbar-hide=\(enabled ? "on" : "off")")
            } else if key == "hotkeys.enabled" {
                let enabled = parseBool(args[3], usage: "Usage: codex-headless config set hotkeys.enabled true|false")
                try configManager.setHotkeysEnabled(enabled)
                print("hotkeys.enabled=\(enabled)")
            } else if key == "confirm-dialog.enabled" {
                let enabled = parseBool(args[3], usage: "Usage: codex-headless config set confirm-dialog.enabled true|false")
                try configManager.setConfirmDialogEnabled(enabled)
                print("confirm-dialog.enabled=\(enabled)")
            } else {
                fail("Usage: codex-headless config reset soft-disconnect-block")
            }
        case "reset":
            guard key == "soft-disconnect-block" else {
                fail("Usage: codex-headless config reset soft-disconnect-block")
            }
            try configManager.clearSoftDisconnectBlock()
            print("soft-disconnect-block=cleared")
        default:
            fail("Unsupported config action: \(action)")
        }

    default:
        printUsage()
        exit(1)
    }
} catch {
    logger.error("CLI command failed: \(error.localizedDescription)")
    fail(error.localizedDescription)
}
