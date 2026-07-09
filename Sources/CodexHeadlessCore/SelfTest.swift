import Foundation

public struct SelfTestResult {
    public var name: String
    public var passed: Bool
    public var detail: String
}

public enum SelfTest {
    public static func run() -> [SelfTestResult] {
        [
            testValidResolution(),
            testInvalidFormat(),
            testTooSmallResolution(),
            testOddDimensions(),
            testRecommendedPresets(),
            testVirtualDisplayScaleModeParsing(),
            testVirtualDisplayPolicyParsing(),
            testInteractionDefaults(),
            testKeepAwakeBackendParsing(),
            testHelperExecutableResolver(),
            testShellTimeout(),
            testCoreDisplayProbeDoesNotCrash(),
            testVirtualDisplayProbeDoesNotCrash(),
            testTouchBarProbeDoesNotCrash()
        ]
    }

    public static func report() -> String {
        let results = run()
        let lines = results.map { result in
            "\(result.passed ? "PASS" : "FAIL")  \(result.name): \(result.detail)"
        }
        let failedCount = results.filter { !$0.passed }.count

        return """
        CodexHeadless Self Test
        -----------------------
        \(lines.joined(separator: "\n"))

        Result: \(failedCount == 0 ? "PASS" : "FAIL (\(failedCount) failed)")
        """
    }

    private static func testValidResolution() -> SelfTestResult {
        do {
            let resolution = try ResolutionManager.parse("2560x1440")
            let passed = resolution == Resolution(width: 2560, height: 1440)
            return SelfTestResult(name: "parse valid resolution", passed: passed, detail: "\(resolution)")
        } catch {
            return SelfTestResult(name: "parse valid resolution", passed: false, detail: error.localizedDescription)
        }
    }

    private static func testInvalidFormat() -> SelfTestResult {
        do {
            _ = try ResolutionManager.parse("2560")
            return SelfTestResult(name: "reject invalid format", passed: false, detail: "unexpected success")
        } catch ResolutionError.invalidFormat {
            return SelfTestResult(name: "reject invalid format", passed: true, detail: "invalid format rejected")
        } catch {
            return SelfTestResult(name: "reject invalid format", passed: false, detail: "wrong error: \(error)")
        }
    }

    private static func testTooSmallResolution() -> SelfTestResult {
        do {
            _ = try ResolutionManager.parse("800x600")
            return SelfTestResult(name: "reject too small resolution", passed: false, detail: "unexpected success")
        } catch ResolutionError.invalidWidth {
            return SelfTestResult(name: "reject too small resolution", passed: true, detail: "width rejected")
        } catch {
            return SelfTestResult(name: "reject too small resolution", passed: false, detail: "wrong error: \(error)")
        }
    }

    private static func testOddDimensions() -> SelfTestResult {
        do {
            _ = try ResolutionManager.parse("1921x1080")
            return SelfTestResult(name: "reject odd dimensions", passed: false, detail: "unexpected success")
        } catch ResolutionError.mustBeEven {
            return SelfTestResult(name: "reject odd dimensions", passed: true, detail: "odd width rejected")
        } catch {
            return SelfTestResult(name: "reject odd dimensions", passed: false, detail: "wrong error: \(error)")
        }
    }

    private static func testRecommendedPresets() -> SelfTestResult {
        let hasLegacyPreset = ResolutionManager.presets.contains(Resolution(width: 1920, height: 1080))
        let hasDefaultPreset = ResolutionManager.presets.contains(Resolution(width: 2560, height: 1440))
        let defaultMatches = ResolutionManager.defaultResolution == Resolution(width: 2560, height: 1440)
        let passed = hasLegacyPreset && hasDefaultPreset && defaultMatches
        return SelfTestResult(
            name: "recommended presets",
            passed: passed,
            detail: "default=\(ResolutionManager.defaultResolution), 1920x1080=\(hasLegacyPreset), 2560x1440=\(hasDefaultPreset)"
        )
    }

    private static func testVirtualDisplayScaleModeParsing() -> SelfTestResult {
        do {
            let standard = try VirtualDisplayScaleMode.parse("standard")
            let hiDPI = try VirtualDisplayScaleMode.parse("HiDPI")
            let passed = standard == .standard && hiDPI == .hidpi
            return SelfTestResult(
                name: "virtual display scale mode parsing",
                passed: passed,
                detail: "standard=\(standard.rawValue), hidpi=\(hiDPI.rawValue)"
            )
        } catch {
            return SelfTestResult(name: "virtual display scale mode parsing", passed: false, detail: error.localizedDescription)
        }
    }

    private static func testVirtualDisplayPolicyParsing() -> SelfTestResult {
        do {
            let auto = try VirtualDisplayPolicy.parse("auto")
            let always = try VirtualDisplayPolicy.parse("ALWAYS")
            let off = try VirtualDisplayPolicy.parse("off")
            let passed = auto == .auto && always == .always && off == .off
            return SelfTestResult(
                name: "virtual display policy parsing",
                passed: passed,
                detail: "auto=\(auto.rawValue), always=\(always.rawValue), off=\(off.rawValue)"
            )
        } catch {
            return SelfTestResult(name: "virtual display policy parsing", passed: false, detail: error.localizedDescription)
        }
    }

    private static func testInteractionDefaults() -> SelfTestResult {
        let hotkeys = HotkeysConfig.default
        let confirmDialog = ConfirmDialogConfig.default
        let passed = hotkeys.enabled
            && hotkeys.enable.displayString == "⌃⌥⌘⇧E"
            && hotkeys.confirm.displayString == "⌃⌥⌘⇧C"
            && hotkeys.restore.displayString == "⌃⌥⌘⇧R"
            && confirmDialog.enabled
            && confirmDialog.showCountdown
        return SelfTestResult(
            name: "interaction defaults",
            passed: passed,
            detail: "hotkeys=\(hotkeys.enable.displayString)/\(hotkeys.confirm.displayString)/\(hotkeys.restore.displayString), dialog=\(confirmDialog.enabled)"
        )
    }

    private static func testKeepAwakeBackendParsing() -> SelfTestResult {
        let caffeinate = KeepAwakeBackend(rawValue: "caffeinate")
        let native = KeepAwakeBackend(rawValue: "native")
        let invalid = KeepAwakeBackend(rawValue: "other")
        let passed = caffeinate == .caffeinate && native == .native && invalid == nil
        return SelfTestResult(
            name: "keep awake backend parsing",
            passed: passed,
            detail: "caffeinate=\(caffeinate != nil), native=\(native != nil), invalidRejected=\(invalid == nil)"
        )
    }

    private static func testHelperExecutableResolver() -> SelfTestResult {
        let resolved = HelperExecutableResolver.resolveExecutable(
            named: "codex-headless",
            currentArgument: "codex-headless",
            environmentPath: "",
            fallbackPaths: ["/definitely/not/installed/codex-headless"]
        )
        let passed = resolved == nil
        return SelfTestResult(
            name: "helper resolver rejects bare argv without PATH",
            passed: passed,
            detail: "resolved=\(resolved ?? "nil")"
        )
    }

    private static func testShellTimeout() -> SelfTestResult {
        do {
            let startedAt = Date()
            let result = try Shell.run("/bin/sleep", ["2"], timeoutSeconds: 0.2)
            let elapsed = Date().timeIntervalSince(startedAt)
            let passed = !result.succeeded && elapsed < 1.5
            return SelfTestResult(
                name: "shell timeout",
                passed: passed,
                detail: String(format: "elapsed=%.2fs, termination=%@", elapsed, result.terminationDescription)
            )
        } catch {
            return SelfTestResult(name: "shell timeout", passed: false, detail: error.localizedDescription)
        }
    }

    private static func testCoreDisplayProbeDoesNotCrash() -> SelfTestResult {
        let probe = CoreDisplayPrivateBridge.shared.probe()
        return SelfTestResult(
            name: "coredisplay probe",
            passed: true,
            detail: "coreDisplayLoaded=\(probe.frameworkLoaded), setUserDisabled=\(probe.setUserDisabledAvailable), skyLightLoaded=\(probe.skyLightLoaded), mainConnection=\(probe.mainConnectionAvailable), configureEnabled=\(probe.configureDisplayEnabledAvailable)"
        )
    }

    private static func testVirtualDisplayProbeDoesNotCrash() -> SelfTestResult {
        let probe = VirtualDisplayManager().probe()
        return SelfTestResult(
            name: "virtual display probe",
            passed: true,
            detail: "runtimeClass=\(probe.cgVirtualDisplayClassAvailable), descriptor=\(probe.descriptorClassAvailable), sdkHeader=\(probe.sdkHeaderAvailable)"
        )
    }

    private static func testTouchBarProbeDoesNotCrash() -> SelfTestResult {
        let probe = TouchBarPrivateBridge.shared.probe()
        return SelfTestResult(
            name: "touch bar probe",
            passed: true,
            detail: "dfrDisplay=\(probe.dfrDisplayLoaded), dfrFoundation=\(probe.dfrFoundationLoaded), dfrBrightness=\(probe.dfrBrightnessLoaded), availableSymbols=\(probe.availableSymbols.count)"
        )
    }
}
