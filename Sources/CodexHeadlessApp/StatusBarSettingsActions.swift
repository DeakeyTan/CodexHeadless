import AppKit
import CodexHeadlessCore

extension StatusBarController {
    func runSettingsMutation(
        name: String,
        failureTitle: String,
        mutation: @escaping () throws -> Void,
        completion: (() -> Void)? = nil
    ) {
        transientOperationTitle = "Updating Settings..."
        updateTitle()
        let submitted = operationCoordinator.submit(name: name, source: "menu", operation: mutation) { [weak self] result in
            guard let self else { return }
            self.transientOperationTitle = nil
            switch result {
            case .success: completion?()
            case .failure(let error): self.showAlert(title: failureTitle, message: error.localizedDescription)
            }
            self.refreshCleanNormalCache(reason: "settings-completion")
        }
        if !submitted {
            transientOperationTitle = nil
            showAlert(title: "CodexHeadless Is Busy", message: "Another operation is already running.")
        }
    }

    private func allowSettingsMutation() -> Bool {
        guard !operationCoordinator.isBusy,
              let state = try? stateStore.read(),
              state.mode == .normal else {
            showAlert(title: "Settings Locked", message: "Restore Clean Normal before changing settings.")
            return false
        }
        guard let assessment = cleanNormalCache.snapshot().usableAssessment(now: Date(), maximumAge: 35),
              assessment.isClean else {
            refreshCleanNormalCache(reason: "settings-preflight")
            showAlert(title: "Settings Locked", message: "Safety status is being refreshed. Try again after Clean Normal is confirmed.")
            return false
        }
        return true
    }

    @objc func enableHeadless() {
        handleEnableRequested(source: "menu")
    }

    @objc func restoreNormal() {
        handleRestoreRequested(source: "menu")
    }

    @objc func confirmHeadless() {
        handleConfirmRequested(source: "menu")
    }

    @objc func toggleKeepAwake() {
        let enabled = !stateStore.load().keepAwake
        runControllerOperation(name: "keep awake", source: "menu", operation: { [controller] in
            try controller.setKeepAwake(enabled)
        }, completion: { [weak self] result in
            if case .failure(let error) = result {
                self?.showAlert(title: "Keep Awake Failed", message: error.localizedDescription)
            }
        })
    }

    @objc func toggleStartAtLogin() {
        guard allowSettingsMutation() else { return }
        let enable = !launchAgentManager.isEnabled()
        runSettingsMutation(name: "start-at-login", failureTitle: "Start at Login Failed", mutation: { [self] in
            launchAgentManager.setEnabled(enable, executablePath: CommandLine.arguments[0])
            var config = try configManager.read()
            config.startAtLogin = enable
            try configManager.save(config)
        })
    }

    @objc func selectPresetResolution(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let rawValue = sender.representedObject as? String else {
            return
        }
        do {
            let resolution = try ResolutionManager.parse(rawValue)
            runSettingsMutation(name: "set-resolution", failureTitle: "Invalid Resolution") { [configManager] in
                try configManager.setResolution(resolution)
            }
        } catch { showAlert(title: "Invalid Resolution", message: error.localizedDescription) }
    }

    @objc func selectVirtualDisplayPolicy(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let rawValue = sender.representedObject as? String else {
            return
        }
        runSettingsMutation(name: "set-virtual-policy", failureTitle: "Virtual Display Policy Failed") { [configManager] in try configManager.setVirtualDisplayPolicy(rawValue) }
    }

    @objc func selectScaleMode(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let rawValue = sender.representedObject as? String else {
            return
        }
        runSettingsMutation(name: "set-scale-mode", failureTitle: "Scale Mode Failed") { [configManager] in try configManager.setVirtualDisplayScaleMode(rawValue) }
    }

    @objc func selectSoftDisconnect(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let enabled = sender.representedObject as? Bool else {
            return
        }
        runSettingsMutation(name: "set-soft-disconnect", failureTitle: "Soft Disconnect Failed") { [configManager] in try configManager.setSoftDisconnectBuiltInDisplay(enabled) }
    }

    @objc func selectTouchBarHide(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let enabled = sender.representedObject as? Bool else {
            return
        }
        runSettingsMutation(name: "set-touchbar", failureTitle: "Touch Bar Hide Failed") { [configManager] in try configManager.setHideTouchBarInHeadless(enabled) }
    }

    @objc func selectHotkeysEnabled(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let enabled = sender.representedObject as? Bool else {
            return
        }
        runSettingsMutation(name: "set-hotkeys", failureTitle: "Hotkeys Failed", mutation: { [configManager] in
            try configManager.setHotkeysEnabled(enabled)
        }, completion: { [weak self] in self?.configureHotkeysIfNeeded(force: true) })
    }

    @objc func selectConfirmDialogEnabled(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let enabled = sender.representedObject as? Bool else {
            return
        }
        runSettingsMutation(name: "set-confirm-dialog", failureTitle: "Confirm Dialog Failed", mutation: { [configManager] in
            try configManager.setConfirmDialogEnabled(enabled)
        }, completion: { [weak self] in if !enabled { self?.confirmDialogController.dismiss(reason: "disabled by menu") } })
    }

    @objc func selectConfirmationPolicy(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let rawValue = sender.representedObject as? String else {
            return
        }
        runSettingsMutation(name: "set-confirmation-policy", failureTitle: "Confirmation Policy Failed") { [configManager] in try configManager.setConfirmationPolicy(rawValue) }
    }

    @objc func selectConfirmationTimeout(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let seconds = sender.representedObject as? Int else {
            return
        }
        runSettingsMutation(name: "set-confirmation-timeout", failureTitle: "Confirmation Timeout Failed") { [configManager] in try configManager.setConfirmationTimeoutSeconds(seconds) }
    }

    @objc func selectSoftDisconnectFailureBehavior(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let rawValue = sender.representedObject as? String else {
            return
        }
        runSettingsMutation(name: "set-handoff", failureTitle: "Display Handoff Setting Failed") { [configManager] in try configManager.setSoftDisconnectFailureBehavior(rawValue) }
    }

    @objc func selectTimingPreset(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let rawValue = sender.representedObject as? String,
              let separator = rawValue.firstIndex(of: "="),
              let value = Int(rawValue[rawValue.index(after: separator)...]) else {
            return
        }

        let key = String(rawValue[..<separator])
        runSettingsMutation(name: "set-timing", failureTitle: "Timing Update Failed") { [configManager] in try configManager.setTimingValue(key: key, value: value) }
    }

    @objc func customTimingValue(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let rawValue = sender.representedObject as? String else {
            return
        }

        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4,
              let currentValue = Int(parts[1]) else {
            return
        }

        let key = parts[0]
        let suffix = parts[2]
        let title = parts[3]
        let isMilliseconds = key.hasSuffix("Milliseconds")
        let maxValue = isMilliseconds ? 10_000 : 120

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter a custom value in \(suffix). Valid range: 0-\(maxValue)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(string: String(currentValue))
        input.placeholderString = suffix
        input.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                guard let value = Int(input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw CodexHeadlessError.invalidConfiguration(message: "Enter a whole number from 0 to \(maxValue).")
                }
                runSettingsMutation(name: "set-custom-timing", failureTitle: "Timing Update Failed") { [configManager] in
                    try configManager.setTimingValue(key: key, value: value)
                }
            } catch {
                showAlert(title: "Timing Update Failed", message: error.localizedDescription)
            }
        }
    }

    @objc func clearSoftDisconnectBlock() {
        guard allowSettingsMutation() else { return }
        runSettingsMutation(name: "clear-soft-block", failureTitle: "Clear Soft Disconnect Block Failed") { [configManager] in try configManager.clearSoftDisconnectBlock() }
    }

    func configurationProfilesMenu() -> NSMenuItem {
        let root = NSMenuItem(title: "Configuration Profiles", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for profile in ConfigurationProfile.allCases {
            let item = menuItem(profile.displayName, #selector(applyConfigurationProfile(_:)))
            item.representedObject = profile.rawValue
            submenu.addItem(item)
        }
        root.submenu = submenu
        return root
    }

    @objc func applyConfigurationProfile(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let rawValue = sender.representedObject as? String,
              let profile = ConfigurationProfile(rawValue: rawValue) else { return }
        let alert = NSAlert()
        alert.messageText = "Apply \(profile.displayName) Profile?"
        alert.informativeText = profile.summary
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runSettingsMutation(name: "apply-profile", failureTitle: "Profile Update Failed") { [configManager] in try configManager.applyProfile(profile) }
    }

    @objc func resetAllSettingsToDefault() {
        guard allowSettingsMutation() else { return }
        let alert = NSAlert()
        alert.messageText = "Reset All Settings to Default?"
        alert.informativeText = "This resets CodexHeadless configuration to the built-in defaults. It does not change the current runtime state; use Restore Normal Mode if Headless Mode is active."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        runSettingsMutation(name: "reset-settings", failureTitle: "Reset Defaults Failed", mutation: { [configManager] in
            try configManager.resetConfigToDefault()
        }, completion: { [weak self] in self?.configureHotkeysIfNeeded(force: true) })
    }

    @objc func selectKeepAwakeBackend(_ sender: NSMenuItem) {
        guard allowSettingsMutation() else { return }
        guard let rawValue = sender.representedObject as? String,
              let backend = KeepAwakeBackend(rawValue: rawValue) else {
            return
        }

        runSettingsMutation(name: "set-keep-awake-backend", failureTitle: "Keep Awake Backend Failed") { [configManager] in try configManager.setKeepAwakeBackend(backend) }
    }

    @objc func customResolution() {
        guard allowSettingsMutation() else { return }
        let config = configManager.load()
        let alert = NSAlert()
        alert.messageText = "Custom Resolution"
        alert.informativeText = "Enter width and height for the configured virtual display."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 220, height: 58)

        let widthField = NSTextField(string: String(config.virtualDisplay.resolution.width))
        widthField.placeholderString = "Width"
        let heightField = NSTextField(string: String(config.virtualDisplay.resolution.height))
        heightField.placeholderString = "Height"
        stack.addArrangedSubview(widthField)
        stack.addArrangedSubview(heightField)
        alert.accessoryView = stack

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                guard let width = Int(widthField.stringValue), let height = Int(heightField.stringValue) else {
                    throw ResolutionError.invalidFormat
                }
                let resolution = Resolution(width: width, height: height)
                try ResolutionManager.validate(resolution)
                runSettingsMutation(name: "set-custom-resolution", failureTitle: "Invalid Resolution") { [configManager] in
                    try configManager.setResolution(resolution)
                }
            } catch {
                showAlert(title: "Invalid Resolution", message: error.localizedDescription)
            }
        }
    }

}
