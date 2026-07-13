import CodexHeadlessCore
import Foundation

enum CLIExecutor {
static func run() {
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "internal-helper" {
    do {
        try CLIInternalHelperCommands.run(Array(args.dropFirst()))
    } catch {
        fail(error.localizedDescription)
    }
}
DiagnosticLoggingPolicy.shared.setEnabled(false)
let logger = CHLogger()
let configManager = ConfigManager(logger: logger)
DiagnosticLoggingPolicy.shared.setEnabled(configManager.load().effectiveDiagnosticLoggingEnabled)
let stateStore = StateStore(logger: logger)
let controller = HeadlessController(
    logger: logger,
    configManager: configManager,
    stateStore: stateStore
)

guard let parsedCommand = CLIParser.parse(args) else {
    printUsage()
    exit(0)
}
let command = parsedCommand.name

do {
    let needsDirectWorkflowLock: Bool = {
        switch command {
        case "repair": return false
        case "virtual-display": return args.dropFirst().first == "start" || args.dropFirst().first == "stop"
        case "soft-disconnect": return args.dropFirst().first == "experiment"
        case "touchbar": return args.dropFirst().first == "experiment"
        case "layout": return args.dropFirst().first != "status"
        case "config": return false // ConfigManager owns the workflow lock and Clean Normal guard.
        default: return false
        }
    }()
    let directWorkflowLease = needsDirectWorkflowLock
        ? try WorkflowOperationLock(logger: logger).acquire(name: "cli-\(command)")
        : nil
    defer { directWorkflowLease?.release() }
    if needsDirectWorkflowLock {
        let assessment = controller.assessCleanNormal()
        guard assessment.isClean else {
            throw CodexHeadlessError.managedResource(
                message: "Clean Normal is required to run `\(args.joined(separator: " "))`: \(assessment.violations.joined(separator: " "))"
            )
        }
    }

    switch command {
    case "--version", "version":
        print("codex-headless \(CodexHeadlessVersion.current)")

    case "__virtual-display-host", "__touchbar-apply", "__soft-disconnect-apply":
        fail("Direct internal helper invocation is not authorized.", code: 64)

    case "status":
        print(controller.statusText())

    case "uninstall-check":
        guard args.count == 1 else { fail("Usage: codex-headless uninstall-check") }
        let assessor = CleanNormalAssessor(
            stateStore: stateStore,
            recoveryJournalStore: RecoveryJournalStore(logger: logger),
            sleepManager: SleepManager(logger: logger, stateStore: stateStore),
            virtualDisplayManager: VirtualDisplayManager(logger: logger, stateStore: stateStore),
            displayManager: DisplayManager(logger: logger)
        )
        let result = UninstallSafetyChecker(
            stateStore: stateStore,
            recoveryJournalStore: RecoveryJournalStore(logger: logger),
            assessor: assessor
        ).check()
        print(result.text)
        if result.exitCode != CLIExitCode.success { exit(result.exitCode) }

    case "uninstall-session":
        var values: [String: String] = [:]
        var index = 1
        while index < args.count {
            guard index + 1 < args.count, args[index].hasPrefix("--") else {
                fail("Invalid uninstall-session arguments.", code: 64)
            }
            values[String(args[index].dropFirst(2))] = args[index + 1]
            index += 2
        }
        guard let appPath = values["installed-app"], let cliPath = values["installed-cli"], let agentPath = values["launch-agent"] else {
            fail("uninstall-session requires installed App, CLI, and LaunchAgent paths.", code: 64)
        }
        let environment = ProcessInfo.processInfo.environment
        let testMode = environment["CODEX_HEADLESS_UNINSTALL_TEST_MODE"] == "1"
        let testRoot = testMode ? environment["CODEX_HEADLESS_UNINSTALL_TEST_ROOT"].map { URL(fileURLWithPath: $0) } : nil
        if testMode && testRoot == nil { fail("Test uninstall-session requires a private test root.", code: 64) }
        let journalStore = RecoveryJournalStore(logger: logger)
        let sleep = SleepManager(logger: logger, stateStore: stateStore, recoveryJournalStore: journalStore)
        let virtual = VirtualDisplayManager(logger: logger, stateStore: stateStore, recoveryJournalStore: journalStore)
        let assessor = CleanNormalAssessor(
            stateStore: stateStore, recoveryJournalStore: journalStore,
            sleepManager: sleep, virtualDisplayManager: virtual,
            displayManager: DisplayManager(logger: logger)
        )
        let coordinator = UninstallSessionCoordinator(
            operationLock: WorkflowOperationLock(logger: logger),
            safetyChecker: UninstallSafetyChecker(
                stateStore: stateStore, recoveryJournalStore: journalStore,
                assessor: assessor, operationLock: WorkflowOperationLock(logger: logger)
            ),
            entryPoints: SystemUninstallEntryPointManager(),
            deleter: SystemUninstallFileDeleter(),
            barrier: FileUninstallSessionBarrier(directory: environment["CODEX_HEADLESS_UNINSTALL_TEST_BARRIER_DIR"].map { URL(fileURLWithPath: $0) }),
            logger: logger
        )
        let result = coordinator.execute(.init(
            installedAppURL: URL(fileURLWithPath: appPath),
            installedCLIURL: URL(fileURLWithPath: cliPath),
            launchAgentURL: URL(fileURLWithPath: agentPath),
            testRootURL: testRoot,
            barrierDirectoryURL: environment["CODEX_HEADLESS_UNINSTALL_TEST_BARRIER_DIR"].map { URL(fileURLWithPath: $0) }
        ))
        print(result.text)
        if result.exitCode != 0 { exit(result.exitCode) }

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
                logger.warn("Option \(args[index]) is accepted for CLI compatibility but is not implemented by the current workflow.")
                index += 1
            default:
                fail("Unknown option: \(args[index])")
            }
        }
        try controller.enableHeadless(resolutionOverride: resolution, rollbackEnabled: rollbackEnabled)
        if stateStore.load().mode == .confirmRequired {
            print("Headless Mode requested. Run `codex-headless confirm` within the rollback window if the setup is good.")
        } else {
            print("Headless Mode enabled. Confirmation is not required by the current policy.")
        }
        print("")
        print(controller.statusText())

    case "off":
        let result = controller.restoreNormal()
        print(CLIOutputFormatter.restore(result))
        print("")
        print(controller.statusText())
        let exitCode = CLIExitCode.restore(result)
        if exitCode != CLIExitCode.success { exit(exitCode) }

    case "repair":
        guard args.count == 2,
              args[1] == "--inspect-orphan-hosts" || args[1] == "--clean-orphan-hosts" else {
            fail("Usage: codex-headless repair --inspect-orphan-hosts")
        }
        let manager = VirtualDisplayManager(logger: logger, stateStore: stateStore)
        let candidates = manager.possibleOrphanHostProcessIDs()
        if args[1] == "--clean-orphan-hosts" {
            print("deprecated: --clean-orphan-hosts cannot safely prove ownership and performs inspection only")
        }
        print("orphan-hosts-found=\(candidates.count)")
        print("orphan-hosts-verified=0")
        print("orphan-hosts-stopped=0")
        print("orphan-hosts-preserved=\(candidates.count)")

    case "confirm":
        if controller.confirm() {
            print("Headless Mode confirmed.")
        } else {
            print("Confirm ignored: current mode is \(stateStore.load().mode.rawValue).")
        }
        print("")
        print(controller.statusText())

    case "doctor":
        let doctor = Doctor(
            configManager: configManager,
            stateStore: stateStore
        )
        print(doctor.report())

    case "layout":
        guard args.count >= 2 else {
            fail("Usage: codex-headless layout status|backup|restore|export PATH|import PATH")
        }

        let displayManager = DisplayManager(logger: logger)
        let layoutStore = DisplayLayoutStore(logger: logger)
        switch args[1] {
        case "status":
            guard args.count == 2 else {
                fail("Usage: codex-headless layout status")
            }
            print("Display Layout")
            print("--------------")
            print(displayManager.statusLines(managedVirtualDisplayID: stateStore.load().virtualDisplayID).joined(separator: "\n"))
            print("")
            print("Snapshot: \(CodexHeadlessPaths.snapshotFile.path)")
            print("Current Profile: \(DisplayLayoutStore.profileKey(for: displayManager.displays()))")
        case "backup":
            guard args.count == 2 else {
                fail("Usage: codex-headless layout backup")
            }
            layoutStore.saveCurrentLayout(
                displayManager: displayManager,
                reason: "manual layout backup",
                includeManagedVirtual: false
            )
            print("layout=backed-up path=\(CodexHeadlessPaths.snapshotFile.path)")
        case "restore":
            guard args.count == 2 else {
                fail("Usage: codex-headless layout restore")
            }
            let snapshot = try layoutStore.loadMatching(displays: displayManager.displays())
            let result = try displayManager.restoreLayout(
                from: snapshot,
                managedVirtualDisplayID: stateStore.load().virtualDisplayID
            )
            print("layout=restored profile=\(snapshot.profileKey) applied=\(result.appliedCount) skipped=\(result.skippedCount)")
        case "export":
            guard args.count == 3 else {
                fail("Usage: codex-headless layout export PATH")
            }
            let exportStore = DisplayLayoutStore(
                logger: logger,
                fileURL: fileURL(from: args[2])
            )
            let snapshot = exportStore.capture(
                from: displayManager.displays(),
                reason: "manual layout export",
                includeManagedVirtual: false
            )
            try exportStore.saveSingleSnapshot(snapshot)
            print("layout=exported profile=\(snapshot.profileKey) path=\(fileURL(from: args[2]).path)")
        case "import":
            guard args.count == 3 else {
                fail("Usage: codex-headless layout import PATH")
            }
            let importStore = DisplayLayoutStore(
                logger: logger,
                fileURL: fileURL(from: args[2])
            )
            let snapshot = try importStore.loadSingleSnapshot()
            let result = try displayManager.restoreLayout(
                from: snapshot,
                managedVirtualDisplayID: stateStore.load().virtualDisplayID
            )
            print("layout=imported profile=\(snapshot.profileKey) applied=\(result.appliedCount) skipped=\(result.skippedCount)")
        default:
            fail("Usage: codex-headless layout status|backup|restore|export PATH|import PATH")
        }

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
            let result = VirtualDisplayManager(stateStore: stateStore).destroyVirtualDisplayIfManaged()
            guard result.completed else {
                fail("virtual-display=stop \(result.summary)", code: 2)
            }
            print("virtual-display=\(result.summary)")
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
            let helperOperationID = directWorkflowLease?.operationID ?? "touchbar-experiment-\(UUID().uuidString.lowercased())"
            let helperCapability = try HelperCapabilityStore().reserve(
                kind: .touchBarApply,
                operationID: helperOperationID,
                expectedExecutablePath: helperPath
            )
            let result = try Shell.run(helperPath, [
                "internal-helper",
                InternalHelperKind.touchBarApply.rawValue,
                helperCapability.capabilityID,
                helperCapability.nonce,
                helperCapability.operationID,
                request.action.rawValue,
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
            let helperOperationID = directWorkflowLease?.operationID ?? "soft-disconnect-experiment-\(UUID().uuidString.lowercased())"
            let helperCapability = try HelperCapabilityStore().reserve(
                kind: .softDisconnectApply,
                operationID: helperOperationID,
                expectedExecutablePath: helperPath
            )
            let helperArgs = [
                "internal-helper",
                InternalHelperKind.softDisconnectApply.rawValue,
                helperCapability.capabilityID,
                helperCapability.nonce,
                helperCapability.operationID,
                String(request.displayID),
                request.action.rawValue,
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
        if args.count == 3, args[1] == "profile" {
            guard let profile = ConfigurationProfile(rawValue: args[2]) else {
                fail("Unknown profile. Use safe-default, 2018-intel-macbook-pro, remote-development, or experimental-maximum-headless.")
            }
            try configManager.applyProfile(profile)
            print("profile=\(profile.rawValue)")
            break
        }
        guard args.count >= 3 else {
            fail("Usage: codex-headless config get resolution|scale-mode|virtual-display-policy|soft-disconnect|keep-awake-backend|touchbar-hide|hotkeys|confirm-dialog|timing | config set resolution WIDTHxHEIGHT | config set scale-mode standard|hidpi | config set virtual-display-policy auto|always|off | config set soft-disconnect on|off | config set keep-awake-backend caffeinate|native | config set touchbar-hide on|off | config set hotkeys.enabled true|false | config set confirm-dialog.enabled true|false | config set timing.KEY VALUE | config reset defaults|soft-disconnect-block")
        }
        let action = args[1]
        let key = args[2]
        let timingKeys = Set(TimingConfig.supportedKeys.map { "timing.\($0)" })
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
            || key == "confirm-dialog.enabled"
            || key == "confirmation"
            || key == "confirmation.policy"
            || key == "confirmation.timeout-seconds"
            || key == "display-handoff"
            || key == "display-handoff.on-soft-disconnect-failure"
            || key == "logging.enabled"
            || key == "defaults"
            || key == "timing"
            || timingKeys.contains(key) else {
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
            } else if key == "confirmation" {
                let confirmation = config.effectiveConfirmation
                print("confirmation.policy=\(confirmation.policy.rawValue)")
                print("confirmation.timeout-seconds=\(confirmation.timeoutSeconds)")
                print("confirmation.dialog-enabled=\(confirmation.dialogEnabled)")
            } else if key == "confirmation.policy" {
                print("confirmation.policy=\(config.effectiveConfirmation.policy.rawValue)")
            } else if key == "confirmation.timeout-seconds" {
                print("confirmation.timeout-seconds=\(config.effectiveConfirmation.timeoutSeconds)")
            } else if key == "display-handoff" {
                let handoff = config.effectiveDisplayHandoff
                print("Keep built-in main during preparation: enforced")
                print("Soft-disconnect failure behavior: \(handoff.onSoftDisconnectFailure.rawValue)")
            } else if key == "display-handoff.on-soft-disconnect-failure" {
                print("display-handoff.on-soft-disconnect-failure=\(config.effectiveDisplayHandoff.onSoftDisconnectFailure.rawValue)")
            } else if key == "logging.enabled" {
                print("logging.enabled=\(config.effectiveDiagnosticLoggingEnabled)")
            } else if key == "timing" {
                let timing = config.effectiveTiming
                print("virtualDisplayEnumerationWaitSeconds=\(timing.virtualDisplayEnumerationWaitSeconds)")
                print("virtualDisplayReportedIDExtraWaitSeconds=\(timing.virtualDisplayReportedIDExtraWaitSeconds)")
                print("softDisconnectDisappearWaitSeconds=\(timing.softDisconnectDisappearWaitSeconds)")
                print("restoreBuiltInShortWaitSeconds=\(timing.restoreBuiltInShortWaitSeconds)")
                print("restorePhysicalDisplayWaitSeconds=\(timing.restorePhysicalDisplayWaitSeconds)")
                print("restorePhysicalDisplayGraceSeconds=\(timing.effectiveRestorePhysicalDisplayGraceSeconds)")
                print("restorePhysicalDisplayGracePollIntervalMilliseconds=\(timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds)")
                print("restoreCooldownSeconds=\(timing.restoreCooldownSeconds)")
                print("restoreCooldownAfterPausedSeconds=\(timing.restoreCooldownAfterPausedSeconds)")
                print("restorePostPromoteStabilizationMilliseconds=\(timing.effectiveRestorePostPromoteStabilizationMilliseconds)")
            } else if key == "defaults" {
                fail("Usage: codex-headless config reset defaults")
            } else {
                print("soft-disconnect-block=\(config.softDisconnectBlockedReason ?? "none")")
            }
        case "set":
            guard args.count == 4 else {
                fail("Usage: codex-headless config set resolution WIDTHxHEIGHT | config set scale-mode standard|hidpi | config set virtual-display-policy auto|always|off | config set soft-disconnect on|off | config set keep-awake-backend caffeinate|native | config set touchbar-hide on|off | config set hotkeys.enabled true|false | config set confirm-dialog.enabled true|false | config set timing.KEY VALUE")
            }
            if timingKeys.contains(key) {
                guard let seconds = Int(args[3]) else {
                    fail("Usage: codex-headless config set \(key) VALUE")
                }
                let timingKey = String(key.dropFirst("timing.".count))
                try configManager.setTimingValue(key: timingKey, value: seconds)
                print("\(timingKey)=\(seconds)")
            } else if key == "resolution" {
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
            } else if key == "confirmation.policy" {
                let policy = try ConfirmationPolicy.parse(args[3])
                try configManager.setConfirmationPolicy(policy.rawValue)
                print("confirmation.policy=\(policy.rawValue)")
            } else if key == "confirmation.timeout-seconds" {
                guard let seconds = Int(args[3]) else {
                    fail("Usage: codex-headless config set confirmation.timeout-seconds SECONDS")
                }
                try configManager.setConfirmationTimeoutSeconds(seconds)
                print("confirmation.timeout-seconds=\(seconds)")
            } else if key == "display-handoff.on-soft-disconnect-failure" {
                let behavior = try SoftDisconnectFailureBehavior.parse(args[3])
                try configManager.setSoftDisconnectFailureBehavior(behavior.rawValue)
                print("display-handoff.on-soft-disconnect-failure=\(behavior.rawValue)")
            } else if key == "logging.enabled" {
                let enabled = parseBool(args[3], usage: "Usage: codex-headless config set logging.enabled true|false")
                try configManager.setDiagnosticLoggingEnabled(enabled)
                if enabled {
                    DiagnosticLoggingPolicy.shared.setEnabled(true)
                    logger.info("[Logging] Diagnostic logging enabled.")
                } else {
                    logger.info("[Logging] Diagnostic logging disabled.")
                    DiagnosticLoggingPolicy.shared.setEnabled(false)
                }
                print("logging.enabled=\(enabled)")
            } else if key == "defaults" {
                fail("Usage: codex-headless config reset defaults")
            } else {
                fail("Usage: codex-headless config reset soft-disconnect-block")
            }
        case "reset":
            guard args.count == 3 else {
                fail("Usage: codex-headless config reset defaults|soft-disconnect-block")
            }
            if key == "soft-disconnect-block" {
                try configManager.clearSoftDisconnectBlock()
                print("soft-disconnect-block=cleared")
            } else if key == "defaults" {
                try configManager.resetConfigToDefault()
                print("config=defaults")
            } else {
                fail("Usage: codex-headless config reset defaults|soft-disconnect-block")
            }
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

}
}
