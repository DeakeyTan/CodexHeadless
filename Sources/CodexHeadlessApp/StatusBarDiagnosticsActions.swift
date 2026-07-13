import AppKit
import CodexHeadlessCore

extension StatusBarController {
    @objc func openLog() {
        try? CodexHeadlessPaths.ensureDirectories()
        if !FileManager.default.fileExists(atPath: CodexHeadlessPaths.logFile.path) {
            FileManager.default.createFile(atPath: CodexHeadlessPaths.logFile.path, contents: nil)
        }
        NSWorkspace.shared.open(CodexHeadlessPaths.logFile)
    }

    @objc func openConfigFolder() {
        try? CodexHeadlessPaths.ensureDirectories()
        NSWorkspace.shared.open(CodexHeadlessPaths.supportDirectory)
    }

    @objc func copyTimingConfigDebugInfo() {
        let timing = configManager.load().effectiveTiming
        let text = """
        virtualDisplayEnumerationWaitSeconds=\(timing.virtualDisplayEnumerationWaitSeconds)
        virtualDisplayReportedIDExtraWaitSeconds=\(timing.virtualDisplayReportedIDExtraWaitSeconds)
        softDisconnectDisappearWaitSeconds=\(timing.softDisconnectDisappearWaitSeconds)
        restoreBuiltInShortWaitSeconds=\(timing.restoreBuiltInShortWaitSeconds)
        restorePhysicalDisplayWaitSeconds=\(timing.restorePhysicalDisplayWaitSeconds)
        restorePhysicalDisplayGraceSeconds=\(timing.effectiveRestorePhysicalDisplayGraceSeconds)
        restorePhysicalDisplayGracePollIntervalMilliseconds=\(timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds)
        restorePostPromoteStabilizationMilliseconds=\(timing.effectiveRestorePostPromoteStabilizationMilliseconds)
        restoreCooldownSeconds=\(timing.restoreCooldownSeconds)
        restoreCooldownAfterPausedSeconds=\(timing.restoreCooldownAfterPausedSeconds)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func resetTimingToDefault() {
        guard allowSettingsMutationForDiagnostics() else { return }
        runSettingsMutation(name: "reset-timing", failureTitle: "Reset Timing Failed") { [configManager] in
            try configManager.resetTimingToDefault()
        }
    }

    private func allowSettingsMutationForDiagnostics() -> Bool {
        guard !operationCoordinator.isBusy, stateStore.load().mode == .normal,
              cleanNormalCache.snapshot().usableAssessment(now: Date(), maximumAge: 35)?.isClean == true else {
            refreshCleanNormalCache(reason: "timing-reset-preflight")
            showAlert(title: "Settings Locked", message: "Restore Clean Normal before changing settings.")
            return false
        }
        return true
    }

    @objc func copyStatus() {
        copyGeneratedReport(name: "status") { [controller] in controller.statusText() }
    }

    @objc func copyDoctorReport() {
        copyGeneratedReport(name: "doctor") { [configManager, stateStore] in
            Doctor(configManager: configManager, stateStore: stateStore).report()
        }
    }

    @objc func copySelfTestReport() {
        copyGeneratedReport(name: "self-test") { SelfTest.report() }
    }

    func copyGeneratedReport(name: String, producer: @escaping () -> String) {
        var report = ""
        let submitted = operationCoordinator.submit(name: "generate \(name)", source: "menu", operation: {
            report = producer()
        }, completion: { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                self.showAlert(title: "Diagnostic Failed", message: error.localizedDescription)
                return
            }
            let suffix = name == "status" ? "\n\n" + self.appInteractionStatusText() : ""
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report + suffix, forType: .string)
        })
        if !submitted {
            showAlert(title: "CodexHeadless Is Busy", message: "Wait for the current operation before generating diagnostics.")
        }
    }

    @objc func quit() {
        guard let reason = terminationBlockReason() else {
            logger.info("CodexHeadless app exiting.")
            NSApp.terminate(nil)
            return
        }
        logger.warn("Quit refused while managed resources are required; Restore Normal Mode first.")
        showAlert(title: "Restore Before Quitting", message: reason)
    }

    func appInteractionStatusText() -> String {
        let config = configManager.load()
        let hotkeys = config.effectiveHotkeys
        let confirmDialog = config.effectiveConfirmDialog
        let countdownText: String
        if let deadline = stateStore.load().rollbackDeadline {
            countdownText = "\(max(0, Int(ceil(deadline.timeIntervalSinceNow))))s"
        } else {
            countdownText = "None"
        }

        return """
        Hotkeys:
          Enabled: \(hotkeys.enabled ? "Yes" : "No")
          Enable: \(hotkeys.enable.displayString) / \(hotkeyManager.statuses[.enable]?.text ?? "Unknown")
          Confirm: \(hotkeys.confirm.displayString) / \(hotkeyManager.statuses[.confirm]?.text ?? "Unknown")
          Restore: \(hotkeys.restore.displayString) / \(hotkeyManager.statuses[.restore]?.text ?? "Unknown")

        Confirm Dialog:
          Enabled: \(confirmDialog.enabled ? "Yes" : "No")
          Visible: \(confirmDialogController.isVisible ? "Yes" : "No")
          Countdown: \(countdownText)
        """
    }

    func markError(_ error: Error) {
        logger.error(error.localizedDescription)
        do {
            try stateStore.transaction { state in
                state.mode = .error
                state.lastError = error.localizedDescription
                state.lastOutcome = .failed
            }
        } catch {
            logger.error("Failed to persist error state: \(error.localizedDescription)")
        }
    }

    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }}
