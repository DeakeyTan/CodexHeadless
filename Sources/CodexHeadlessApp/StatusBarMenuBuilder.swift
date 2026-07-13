import AppKit
import CodexHeadlessCore

extension StatusBarController {
    func virtualDisplayMenu(config: AppConfig) -> NSMenuItem {
        let item = NSMenuItem(title: "Virtual Display", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let currentPolicy = VirtualDisplayPolicy.effectivePolicy(for: config.virtualDisplay)
        submenu.addItem(identified(disabledItem("Policy: \(currentPolicy.rawValue)"), id: "virtual-policy-summary"))
        submenu.addItem(identified(disabledItem("Resolution: \(config.virtualDisplay.resolution)"), id: "virtual-resolution-summary"))
        submenu.addItem(identified(disabledItem("Scale Mode: \(config.virtualDisplay.scaleMode)"), id: "virtual-scale-summary"))

        submenu.addItem(.separator())
        for policy in [VirtualDisplayPolicy.auto, .always, .off] {
            let policyItem = NSMenuItem(title: "Policy: \(policy.rawValue)", action: #selector(selectVirtualDisplayPolicy(_:)), keyEquivalent: "")
            policyItem.target = self
            policyItem.representedObject = policy.rawValue
            policyItem.state = policy == currentPolicy ? .on : .off
            submenu.addItem(policyItem)
        }

        submenu.addItem(.separator())
        for scaleMode in [VirtualDisplayScaleMode.standard, .hidpi] {
            let scaleItem = NSMenuItem(title: "Scale: \(scaleMode.rawValue)", action: #selector(selectScaleMode(_:)), keyEquivalent: "")
            scaleItem.target = self
            scaleItem.representedObject = scaleMode.rawValue
            scaleItem.state = scaleMode.rawValue == config.virtualDisplay.scaleMode ? .on : .off
            submenu.addItem(scaleItem)
        }

        submenu.addItem(.separator())
        for preset in ResolutionManager.presets {
            let presetItem = NSMenuItem(title: "Preset: \(preset)", action: #selector(selectPresetResolution(_:)), keyEquivalent: "")
            presetItem.target = self
            presetItem.representedObject = preset.description
            presetItem.state = preset == config.virtualDisplay.resolution ? .on : .off
            submenu.addItem(presetItem)
        }

        submenu.addItem(.separator())
        submenu.addItem(menuItem("Custom Resolution...", #selector(customResolution)))
        item.submenu = submenu
        return item
    }

    func displaySafetyMenu(config: AppConfig) -> NSMenuItem {
        let item = NSMenuItem(title: "Display & Touch Bar Safety", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for option in [true, false] {
            let title = option ? "Soft Disconnect: On" : "Soft Disconnect: Off"
            let softItem = NSMenuItem(title: title, action: #selector(selectSoftDisconnect(_:)), keyEquivalent: "")
            softItem.target = self
            softItem.representedObject = option
            softItem.state = (config.softDisconnectBuiltInDisplay == true) == option ? .on : .off
            submenu.addItem(softItem)
        }

        submenu.addItem(.separator())
        let handoff = config.effectiveDisplayHandoff
        for behavior in SoftDisconnectFailureBehavior.allCases {
            let handoffItem = NSMenuItem(
                title: "On Disconnect Failure: \(behavior.rawValue)",
                action: #selector(selectSoftDisconnectFailureBehavior(_:)),
                keyEquivalent: ""
            )
            handoffItem.target = self
            handoffItem.representedObject = behavior.rawValue
            handoffItem.state = behavior == handoff.onSoftDisconnectFailure ? .on : .off
            submenu.addItem(handoffItem)
        }

        submenu.addItem(.separator())
        for option in [true, false] {
            let title = option ? "Touch Bar Hide: On" : "Touch Bar Hide: Off"
            let touchBarItem = NSMenuItem(title: title, action: #selector(selectTouchBarHide(_:)), keyEquivalent: "")
            touchBarItem.target = self
            touchBarItem.representedObject = option
            touchBarItem.state = (config.hideTouchBarInHeadless == true) == option ? .on : .off
            submenu.addItem(touchBarItem)
        }

        submenu.addItem(.separator())
        let blockTitle = identified(disabledItem("Soft Disconnect Blocked"), id: "soft-block-title")
        let blockReason = identified(disabledItem(config.softDisconnectBlockedReason ?? ""), id: "soft-block-reason")
        let clearBlock = identified(menuItem("Clear Soft Disconnect Block", #selector(clearSoftDisconnectBlock)), id: "soft-block-clear")
        let blockHidden = config.softDisconnectBlockedReason == nil
        blockTitle.isHidden = blockHidden
        blockReason.isHidden = blockHidden
        clearBlock.isHidden = blockHidden
        submenu.addItem(blockTitle)
        submenu.addItem(blockReason)
        submenu.addItem(clearBlock)

        item.submenu = submenu
        return item
    }

    func diagnosticsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(menuItem("Copy Status", #selector(copyStatus)))
        submenu.addItem(menuItem("Copy Doctor Report", #selector(copyDoctorReport)))
        submenu.addItem(menuItem("Copy Self Test Report", #selector(copySelfTestReport)))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Open Log", #selector(openLog)))
        submenu.addItem(menuItem("Open Config Folder", #selector(openConfigFolder)))
        item.submenu = submenu
        return item
    }

    func hotkeysMenu(config: AppConfig) -> NSMenuItem {
        let hotkeys = config.effectiveHotkeys
        let item = NSMenuItem(title: hotkeys.enabled ? "Hotkeys: On" : "Hotkeys: Off", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for option in [true, false] {
            let hotkeyItem = NSMenuItem(title: option ? "Hotkeys: On" : "Hotkeys: Off", action: #selector(selectHotkeysEnabled(_:)), keyEquivalent: "")
            hotkeyItem.target = self
            hotkeyItem.representedObject = option
            hotkeyItem.state = hotkeys.enabled == option ? .on : .off
            submenu.addItem(hotkeyItem)
        }

        submenu.addItem(.separator())
        submenu.addItem(disabledItem("Enable: \(hotkeys.enable.displayString) / \(hotkeyManager.statuses[.enable]?.text ?? "Pending")"))
        submenu.addItem(disabledItem("Confirm: \(hotkeys.confirm.displayString) / \(hotkeyManager.statuses[.confirm]?.text ?? "Pending")"))
        submenu.addItem(disabledItem("Restore: \(hotkeys.restore.displayString) / \(hotkeyManager.statuses[.restore]?.text ?? "Pending")"))

        item.submenu = submenu
        return item
    }

    func confirmDialogMenu(config: AppConfig) -> NSMenuItem {
        let confirmDialog = config.effectiveConfirmDialog
        let confirmation = config.effectiveConfirmation
        let item = NSMenuItem(title: "Confirmation: \(confirmation.policy.rawValue)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for policy in ConfirmationPolicy.allCases {
            let policyItem = NSMenuItem(title: "Policy: \(policy.rawValue)", action: #selector(selectConfirmationPolicy(_:)), keyEquivalent: "")
            policyItem.target = self
            policyItem.representedObject = policy.rawValue
            policyItem.state = policy == confirmation.policy ? .on : .off
            submenu.addItem(policyItem)
        }

        submenu.addItem(.separator())
        submenu.addItem(identified(disabledItem("Timeout: \(confirmation.timeoutSeconds)s"), id: "confirmation-timeout-summary"))
        for seconds in [15, 30, 45, 60] {
            let timeoutItem = NSMenuItem(title: "Timeout: \(seconds)s", action: #selector(selectConfirmationTimeout(_:)), keyEquivalent: "")
            timeoutItem.target = self
            timeoutItem.representedObject = seconds
            timeoutItem.state = seconds == confirmation.timeoutSeconds ? .on : .off
            submenu.addItem(timeoutItem)
        }
        let warning = identified(disabledItem("Warning: automatic rollback confirmation is disabled."), id: "confirmation-warning")
        warning.isHidden = confirmation.policy != .never
        submenu.addItem(warning)

        submenu.addItem(.separator())

        for option in [true, false] {
            let dialogItem = NSMenuItem(title: option ? "Confirm Dialog: On" : "Confirm Dialog: Off", action: #selector(selectConfirmDialogEnabled(_:)), keyEquivalent: "")
            dialogItem.target = self
            dialogItem.representedObject = option
            dialogItem.state = confirmDialog.enabled == option ? .on : .off
            submenu.addItem(dialogItem)
        }

        submenu.addItem(.separator())
        submenu.addItem(disabledItem("Hotkey hints: \(confirmDialog.showHotkeyHints ? "On" : "Off")"))
        submenu.addItem(disabledItem("Countdown: \(confirmDialog.showCountdown ? "On" : "Off")"))

        item.submenu = submenu
        return item
    }

    func timingMenu(config: AppConfig) -> NSMenuItem {
        let timing = config.effectiveTiming
        let item = NSMenuItem(title: "Timing", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        submenu.addItem(identified(disabledItem("Virtual Display Enumeration: \(timing.virtualDisplayEnumerationWaitSeconds)s"), id: "timing-virtual-enumeration"))
        submenu.addItem(identified(disabledItem("Reported ID Extra Wait: \(timing.virtualDisplayReportedIDExtraWaitSeconds)s"), id: "timing-reported-id"))
        submenu.addItem(identified(disabledItem("Soft Disconnect Verify: \(timing.softDisconnectDisappearWaitSeconds)s"), id: "timing-soft-disconnect"))
        submenu.addItem(identified(disabledItem("Restore Built-in Short Wait: \(timing.restoreBuiltInShortWaitSeconds)s"), id: "timing-built-in"))
        submenu.addItem(identified(disabledItem("Restore Physical Wait: \(timing.restorePhysicalDisplayWaitSeconds)s"), id: "timing-physical"))
        submenu.addItem(identified(disabledItem("Restore Grace: \(timing.effectiveRestorePhysicalDisplayGraceSeconds)s"), id: "timing-grace"))
        submenu.addItem(identified(disabledItem("Grace Poll Interval: \(timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds)ms"), id: "timing-poll"))
        submenu.addItem(identified(disabledItem("Post-promote Stabilization: \(timing.effectiveRestorePostPromoteStabilizationMilliseconds)ms"), id: "timing-stabilization"))
        submenu.addItem(identified(disabledItem("Restore Cooldown: \(timing.restoreCooldownSeconds)s"), id: "timing-cooldown"))
        submenu.addItem(identified(disabledItem("Paused Restore Cooldown: \(timing.restoreCooldownAfterPausedSeconds)s"), id: "timing-paused-cooldown"))

        submenu.addItem(.separator())
        submenu.addItem(timingPresetMenu(
            title: "Restore Physical Display Wait",
            key: "restorePhysicalDisplayWaitSeconds",
            currentValue: timing.restorePhysicalDisplayWaitSeconds,
            presets: [5, 10, 15, 20, 30],
            suffix: "s"
        ))
        submenu.addItem(timingPresetMenu(
            title: "Restore Physical Display Grace",
            key: "restorePhysicalDisplayGraceSeconds",
            currentValue: timing.effectiveRestorePhysicalDisplayGraceSeconds,
            presets: [0, 1, 2, 3, 5],
            suffix: "s"
        ))
        submenu.addItem(timingPresetMenu(
            title: "Grace Poll Interval",
            key: "restorePhysicalDisplayGracePollIntervalMilliseconds",
            currentValue: timing.effectiveRestorePhysicalDisplayGracePollIntervalMilliseconds,
            presets: [100, 250, 500, 1000],
            suffix: "ms"
        ))
        submenu.addItem(timingPresetMenu(
            title: "Post-promote Stabilization",
            key: "restorePostPromoteStabilizationMilliseconds",
            currentValue: timing.effectiveRestorePostPromoteStabilizationMilliseconds,
            presets: [0, 500, 750, 1000, 1500],
            suffix: "ms"
        ))
        submenu.addItem(timingPresetMenu(
            title: "Restore Cooldown",
            key: "restoreCooldownSeconds",
            currentValue: timing.restoreCooldownSeconds,
            presets: [5, 10, 20, 30],
            suffix: "s"
        ))
        submenu.addItem(timingPresetMenu(
            title: "Paused Restore Cooldown",
            key: "restoreCooldownAfterPausedSeconds",
            currentValue: timing.restoreCooldownAfterPausedSeconds,
            presets: [10, 20, 30, 45],
            suffix: "s"
        ))

        submenu.addItem(.separator())
        submenu.addItem(menuItem("Copy Timing Config Debug Info", #selector(copyTimingConfigDebugInfo)))
        submenu.addItem(menuItem("Open Config Folder", #selector(openConfigFolder)))
        submenu.addItem(menuItem("Reset Timing to Default", #selector(resetTimingToDefault)))

        item.submenu = submenu
        return item
    }

    func timingPresetMenu(
        title: String,
        key: String,
        currentValue: Int,
        presets: [Int],
        suffix: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in presets {
            let label = value == 0 ? "Off" : "\(value)\(suffix)"
            let presetItem = NSMenuItem(title: label, action: #selector(selectTimingPreset(_:)), keyEquivalent: "")
            presetItem.target = self
            presetItem.representedObject = "\(key)=\(value)"
            presetItem.state = value == currentValue ? .on : .off
            submenu.addItem(presetItem)
        }
        submenu.addItem(.separator())
        let customItem = NSMenuItem(title: "Custom...", action: #selector(customTimingValue(_:)), keyEquivalent: "")
        customItem.target = self
        customItem.representedObject = "\(key)|\(currentValue)|\(suffix)|\(title)"
        submenu.addItem(customItem)
        item.submenu = submenu
        return item
    }

    func keepAwakeBackendMenu(config: AppConfig) -> NSMenuItem {
        let current = config.keepAwakeBackend ?? .caffeinate
        let item = NSMenuItem(title: "Keep Awake Backend", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for backend in [KeepAwakeBackend.caffeinate] {
            let backendItem = NSMenuItem(
                title: backend == .caffeinate ? "caffeinate (CLI-safe)" : "native (App only)",
                action: #selector(selectKeepAwakeBackend(_:)),
                keyEquivalent: ""
            )
            backendItem.target = self
            backendItem.representedObject = backend.rawValue
            backendItem.state = backend == current ? .on : .off
            submenu.addItem(backendItem)
        }

        item.submenu = submenu
        return item
    }

    func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func addPhaseItems(to menu: NSMenu, state: RuntimeState) {
        presenter.phaseLines(for: state).forEach { menu.addItem(disabledItem($0)) }
    }

}
