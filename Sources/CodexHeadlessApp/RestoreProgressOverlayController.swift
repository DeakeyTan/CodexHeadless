import AppKit
import CodexHeadlessCore

final class RestoreProgressOverlayController {
    private var panel: NSPanel?
    private let titleLabel = NSTextField(labelWithString: "Restoring Normal Mode...")
    private let bodyLabel = NSTextField(labelWithString: "")

    func update(state: RuntimeState) {
        let phase = RuntimePhaseFormatter.phase(state)
        guard shouldShowOverlay(mode: state.mode, phase: phase) else {
            close()
            return
        }

        ensurePanel()
        titleLabel.stringValue = title(for: phase)
        bodyLabel.stringValue = body(for: state, phase: phase)
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func shouldShowOverlay(mode: HeadlessMode, phase: RuntimePhase) -> Bool {
        guard mode == .restoring || phase == .restorePaused else {
            return false
        }

        switch phase {
        case .restoringBuiltInDisplay,
             .waitingForPhysicalDisplay,
             .restorePaused,
             .promotingPhysicalDisplay,
             .keepingExternalDisplayAsMain,
             .stoppingVirtualDisplay:
            return true
        default:
            return false
        }
    }

    private func ensurePanel() {
        guard panel == nil else {
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 132),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true

        let content = NSView(frame: panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 360, height: 132))
        titleLabel.frame = NSRect(x: 20, y: 82, width: 320, height: 24)
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.textColor = .white
        bodyLabel.frame = NSRect(x: 20, y: 24, width: 320, height: 54)
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .white
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.maximumNumberOfLines = 3
        content.addSubview(titleLabel)
        content.addSubview(bodyLabel)
        panel.contentView = content
        self.panel = panel
    }

    private func positionPanel() {
        guard let panel else {
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else {
            return
        }

        let x = frame.midX - panel.frame.width / 2
        let y = frame.maxY - panel.frame.height - 72
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func title(for phase: RuntimePhase) -> String {
        switch phase {
        case .restorePaused:
            return "Restore is waiting for a physical display..."
        case .stoppingVirtualDisplay:
            return "Closing virtual display..."
        default:
            return "Restoring Normal Mode..."
        }
    }

    private func body(for state: RuntimeState, phase: RuntimePhase) -> String {
        let countdown: String
        if let remaining = RuntimePhaseFormatter.deadlineRemainingSeconds(state) {
            countdown = "\nTimeout: \(remaining)s"
        } else {
            countdown = ""
        }

        switch phase {
        case .restorePaused:
            return "The virtual display is kept alive for safety.\nPress Restore again after the built-in display appears."
        case .stoppingVirtualDisplay:
            return "Windows may move back to the built-in display shortly.\(countdown)"
        default:
            return "Switching back to physical display.\nVirtual display will close shortly.\(countdown)"
        }
    }

    private func close() {
        panel?.orderOut(nil)
    }
}
