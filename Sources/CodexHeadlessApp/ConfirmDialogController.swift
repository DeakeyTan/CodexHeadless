import AppKit
import CodexHeadlessCore
import Foundation

final class ConfirmDialogController: NSObject, NSWindowDelegate {
    private let logger: CHLogger
    private var panel: NSPanel?
    private var countdownLabel: NSTextField?
    private var timer: Timer?
    private var deadline: Date?
    private var onConfirm: (() -> Void)?
    private var onRollback: (() -> Void)?
    private var isProgrammaticDismiss = false

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(logger: CHLogger) {
        self.logger = logger
    }

    func show(
        deadline: Date?,
        config: ConfirmDialogConfig,
        onConfirm: @escaping () -> Void,
        onRollback: @escaping () -> Void
    ) {
        guard config.enabled else {
            return
        }

        self.deadline = deadline
        self.onConfirm = onConfirm
        self.onRollback = onRollback

        if panel == nil {
            panel = buildPanel(showHotkeyHints: config.showHotkeyHints, showCountdown: config.showCountdown)
        }

        updateCountdown()
        logger.info("[Dialog] Show confirm dialog, timeout=\(config.timeoutSeconds)")
        panel?.center()
        panel?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        timer?.invalidate()
        if config.showCountdown {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateCountdown()
            }
        }
    }

    func update(deadline: Date?) {
        self.deadline = deadline
        updateCountdown()
    }

    func dismiss(reason: String) {
        guard panel != nil else {
            return
        }
        logger.info("[Dialog] Close confirm dialog, reason=\(reason)")
        timer?.invalidate()
        timer = nil
        isProgrammaticDismiss = true
        panel?.close()
        isProgrammaticDismiss = false
        panel = nil
        countdownLabel = nil
        onConfirm = nil
        onRollback = nil
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        if panel != nil && !isProgrammaticDismiss {
            logger.info("[Dialog] User closed confirm dialog; ConfirmRequired state remains pending.")
        }
        panel = nil
        countdownLabel = nil
    }

    private func buildPanel(showHotkeyHints: Bool, showCountdown: Bool) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "CodexHeadless"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView = content

        let title = NSTextField(labelWithString: "Headless Mode Enabled")
        title.font = .boldSystemFont(ofSize: 18)
        title.frame = NSRect(x: 24, y: 190, width: 412, height: 24)
        content.addSubview(title)

        let body = NSTextField(wrappingLabelWithString: "Confirm that remote access, display output, and the built-in display state are working as expected.")
        body.frame = NSRect(x: 24, y: 138, width: 412, height: 44)
        content.addSubview(body)

        let hintText = showHotkeyHints
            ? "Confirm: ⌃⌥⌘⇧C    Rollback: ⌃⌥⌘⇧R"
            : ""
        let hint = NSTextField(labelWithString: hintText)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 24, y: 108, width: 412, height: 20)
        content.addSubview(hint)

        let countdown = NSTextField(labelWithString: showCountdown ? "Auto rollback in 30s" : "")
        countdown.textColor = .secondaryLabelColor
        countdown.frame = NSRect(x: 24, y: 80, width: 412, height: 20)
        content.addSubview(countdown)
        countdownLabel = countdown

        let rollbackButton = NSButton(title: "Rollback Now", target: self, action: #selector(rollbackClicked))
        rollbackButton.frame = NSRect(x: 218, y: 28, width: 112, height: 32)
        content.addSubview(rollbackButton)

        let confirmButton = NSButton(title: "Confirm", target: self, action: #selector(confirmClicked))
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"
        confirmButton.frame = NSRect(x: 340, y: 28, width: 96, height: 32)
        content.addSubview(confirmButton)

        return panel
    }

    private func updateCountdown() {
        guard let countdownLabel else {
            return
        }
        guard let deadline else {
            countdownLabel.stringValue = "Auto rollback pending"
            return
        }
        let seconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        countdownLabel.stringValue = "Auto rollback in \(seconds)s"
    }

    @objc private func confirmClicked() {
        logger.info("[Dialog] Confirm clicked")
        onConfirm?()
    }

    @objc private func rollbackClicked() {
        logger.info("[Dialog] Rollback clicked")
        onRollback?()
    }
}
