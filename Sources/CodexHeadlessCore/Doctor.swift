import Darwin
import Foundation

public final class Doctor {
    private let configManager: ConfigManager
    private let stateStore: StateStore
    private let displayManager: DisplayManager
    private let builtInDisplayManager: BuiltInDisplayManager

    public init(
        configManager: ConfigManager = ConfigManager(),
        stateStore: StateStore = StateStore(),
        displayManager: DisplayManager = DisplayManager(),
        builtInDisplayManager: BuiltInDisplayManager = BuiltInDisplayManager()
    ) {
        self.configManager = configManager
        self.stateStore = stateStore
        self.displayManager = displayManager
        self.builtInDisplayManager = builtInDisplayManager
    }

    public func report() -> String {
        let config = configManager.load()
        let virtualDisplayPolicy = VirtualDisplayPolicy.effectivePolicy(for: config.virtualDisplay)
        let state = stateStore.load()
        let displays = displayManager.displays()
        let builtIn = displays.first { $0.isBuiltIn }
        let managedVirtual = state.virtualDisplayID.flatMap { id in
            displays.first { $0.id == id }
        }
        let external = displays.first { display in
            !display.isBuiltIn
                && display.isActive
                && display.isOnline
                && display.id != state.virtualDisplayID
        }
        let main = displays.first { $0.isMain }
        let brightnessCommand = brightnessCommandPath()
        let caffeinateText = state.caffeinatePID.map { processIsRunning($0) ? "Running (PID \($0))" : "Recorded but not running (PID \($0))" } ?? "Not managed"
        let mainText = main.map { display -> String in
            if display.id == state.virtualDisplayID {
                return "Managed Virtual"
            }
            return display.isBuiltIn ? "Built-in" : "External / Dummy"
        } ?? "Unknown"
        let virtualDisplayText = managedVirtual.map {
            "ID \($0.id), \($0.width)x\($0.height), main=\($0.isMain ? "yes" : "no")"
        } ?? "Not active"

        return """
        CodexHeadless Doctor
        --------------------
        Overall: \(overallStatus(external: external, managedVirtual: managedVirtual, policy: virtualDisplayPolicy))

        Runtime:
          Mode: \(state.mode.rawValue)
          Phase: \(RuntimePhaseFormatter.phase(state).rawValue)
          Current Step: \(RuntimePhaseFormatter.message(state))
          Rollback: \(state.rollbackConfirmed ? "Confirmed" : "Pending")

        Files:
          Config: \(fileStatus(CodexHeadlessPaths.configFile))
          State: \(fileStatus(CodexHeadlessPaths.stateFile))
          Log: \(fileStatus(CodexHeadlessPaths.logFile))

        Displays:
          Count: \(displays.count)
          Note: \(displays.isEmpty ? "No displays visible to this process; run from the target GUI login session if this looks wrong." : "Display enumeration available.")
          Built-in: \(builtIn.map { "\($0.width)x\($0.height), main=\($0.isMain ? "yes" : "no")" } ?? "Not detected")
          External / Dummy: \(external.map { "ID \($0.id), \($0.width)x\($0.height), main=\($0.isMain ? "yes" : "no")" } ?? "Not detected")
          Managed Virtual: \(virtualDisplayText)
          Main: \(mainText)

        Virtual Display:
          Policy: \(virtualDisplayPolicy.rawValue)
          Active: \(state.virtualDisplayCreated ? "Yes" : "No")
          Requested: \(state.virtualDisplayCreated ? "\(state.virtualDisplayRequestedResolution ?? config.virtualDisplay.resolution) @ \(state.virtualDisplayRefreshRate ?? config.virtualDisplay.refreshRate)Hz" : "Not active")
          Scale Mode: \(state.virtualDisplayCreated ? (state.virtualDisplayScaleMode ?? config.virtualDisplay.scaleMode) : config.virtualDisplay.scaleMode)
          Host PID: \(state.virtualDisplayPID.map(String.init) ?? "Not running")

        Keep Awake:
          State: \(state.keepAwake ? "On" : "Off")
          Backend: \(state.keepAwakeBackend ?? config.keepAwakeBackend?.rawValue ?? KeepAwakeBackend.caffeinate.rawValue)
          Caffeinate: \(caffeinateText)
          pmset: \(pmsetSummary())

        Timing:
          Virtual display enumeration wait: \(config.effectiveTiming.virtualDisplayEnumerationWaitSeconds)s
          Reported ID extra wait: \(config.effectiveTiming.virtualDisplayReportedIDExtraWaitSeconds)s
          Soft-disconnect disappear wait: \(config.effectiveTiming.softDisconnectDisappearWaitSeconds)s
          Restore built-in short wait: \(config.effectiveTiming.restoreBuiltInShortWaitSeconds)s
          Restore physical display wait: \(config.effectiveTiming.restorePhysicalDisplayWaitSeconds)s
          Restore cooldown: \(config.effectiveTiming.restoreCooldownSeconds)s
          Restore paused cooldown: \(config.effectiveTiming.restoreCooldownAfterPausedSeconds)s

        Brightness Fallback:
          IOKit readable: \(builtInDisplayManager.currentBrightness() == nil ? "No" : "Yes")
          brightness command: \(brightnessCommand ?? "Not found")
          AppleScript key events: Requires Accessibility permission for Terminal/iTerm/CodexHeadless
          Last method: \(state.builtInBrightnessMethod ?? "None")

        Soft Disconnect:
          CoreDisplay SetUserDisabled: \(CoreDisplayPrivateBridge.shared.probe().setUserDisabledAvailable ? "Available" : "Unavailable")
          SkyLight MainConnection: \(CoreDisplayPrivateBridge.shared.probe().mainConnectionAvailable ? "Available" : "Unavailable")
          SkyLight ConfigureDisplayEnabled: \(CoreDisplayPrivateBridge.shared.probe().configureDisplayEnabledAvailable ? "Available" : "Unavailable")
          State: \(state.builtInSoftDisconnected == true ? "Soft-disconnected" : "Not soft-disconnected")
          Last method: \(state.builtInSoftDisconnectMethod ?? "None")
          Last message: \(state.builtInSoftDisconnectLastMessage ?? "None")
          Blocked reason: \(config.softDisconnectBlockedReason ?? "None")

        Touch Bar:
          Config: \(config.hideTouchBarInHeadless == true ? "Hide in Headless Mode" : "Do not hide")
          State: \(state.touchBarHidden == true ? "Hidden" : "Not hidden")
          Last method: \(state.touchBarHideMethod ?? "None")
          Last message: \(state.touchBarLastMessage ?? "None")

        Config:
          Virtual Display Policy: \(virtualDisplayPolicy.rawValue)
          Resolution: \(config.virtualDisplay.resolution)
          Scale Mode: \(config.virtualDisplay.scaleMode)
          Keep Awake Backend: \(config.keepAwakeBackend?.rawValue ?? KeepAwakeBackend.caffeinate.rawValue)
          Rollback: \(config.rollback.enabled ? "On, \(config.rollback.timeoutSeconds)s" : "Off")
          Soft Disconnect: \(config.softDisconnectBuiltInDisplay == true ? "Enabled (experimental)" : "Disabled")

        Suggested Next Step:
          \(suggestedNextStep(state: state, hasAlternativeDisplay: external != nil || managedVirtual != nil, policy: virtualDisplayPolicy, displayCount: displays.count))
        """
    }

    private func fileStatus(_ url: URL) -> String {
        FileManager.default.fileExists(atPath: url.path) ? "OK (\(url.path))" : "Missing (\(url.path))"
    }

    private func brightnessCommandPath() -> String? {
        ["/opt/homebrew/bin/brightness", "/usr/local/bin/brightness"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func processIsRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    private func pmsetSummary() -> String {
        do {
            let result = try Shell.run("/usr/bin/pmset", ["-g", "custom"])
            guard result.succeeded else {
                return "Unavailable"
            }

            let interesting = result.output
                .split(separator: "\n")
                .filter { line in
                    let text = line.trimmingCharacters(in: .whitespaces)
                    return text.hasPrefix("sleep")
                        || text.hasPrefix("displaysleep")
                        || text.hasPrefix("disksleep")
                }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .reduce(into: [String]()) { uniqueLines, line in
                    if !uniqueLines.contains(line) {
                        uniqueLines.append(line)
                    }
                }

            return interesting.isEmpty ? "Available" : interesting.joined(separator: "; ")
        } catch {
            return "Unavailable"
        }
    }

    private func overallStatus(
        external: DisplayInfo?,
        managedVirtual: DisplayInfo?,
        policy: VirtualDisplayPolicy
    ) -> String {
        if external != nil {
            return "Ready for Headless with external/dummy display"
        }
        if managedVirtual != nil {
            return "Ready for Headless with managed virtual display"
        }
        if policy != .off {
            return "Can create managed virtual display on `codex-headless on`"
        }
        return "Needs HDMI Dummy / external display or virtual-display-policy auto|always"
    }

    private func suggestedNextStep(
        state: RuntimeState,
        hasAlternativeDisplay: Bool,
        policy: VirtualDisplayPolicy,
        displayCount: Int
    ) -> String {
        guard hasAlternativeDisplay else {
            if displayCount == 0 {
                return "No displays are visible to this process. Run from the target GUI login session; with virtual-display-policy \(policy.rawValue), `codex-headless on` can still create a managed virtual display if allowed by macOS."
            }
            if policy == .off {
                return "Insert HDMI Dummy Plug or set `virtual-display-policy auto|always`, then run `codex-headless doctor` again."
            }
            return "Run `codex-headless on`; policy \(policy.rawValue) can create a managed virtual display when no external/dummy display is active."
        }

        switch state.mode {
        case .headless:
            return "Already Headless. Use `codex-headless off` to restore Normal Mode."
        case .confirmRequired:
            return "Run `codex-headless confirm` if the screen state is good, or `codex-headless off` to roll back."
        case .normal:
            return "Run `codex-headless on`, then `codex-headless confirm` if the screen state is good."
        case .fallback:
            return "Fallback is active. Check `codex-headless status` and logs, then confirm or restore."
        case .preparing:
            return "A transition is in progress. Check `codex-headless status`."
        case .restoring:
            return "Restore is in progress. Keep the managed virtual display alive until a physical display is available."
        case .error:
            return "Run `codex-headless off`, then inspect `codex-headless log --tail 100`."
        }
    }
}
