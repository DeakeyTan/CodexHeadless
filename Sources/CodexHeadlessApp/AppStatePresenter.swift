import CodexHeadlessCore
import Foundation

struct AppStatePresenter {
    func statusTitle(for state: RuntimeState) -> String {
        if RuntimePhaseFormatter.cooldownRemainingSeconds(state) > 0 { return "CH: Cooldown" }
        switch state.mode {
        case .normal: return "CH"
        case .preparing: return "CH: Prep"
        case .confirmRequired: return "CH: Wait"
        case .headless: return "CH: On"
        case .fallback: return "CH: Fall"
        case .restoring: return "CH: Restoring"
        case .error: return "CH: Err"
        case .recoveryRequired: return "CH: Recovery"
        }
    }

    func builtInHandling(for state: RuntimeState) -> String {
        if state.builtInSoftDisconnected == true { return "Soft-disconnected" }
        if state.builtInBrightnessDimmed == true { return "Dimmed" }
        return "Active"
    }

    func phaseLines(for state: RuntimeState) -> [String] {
        let phase = RuntimePhaseFormatter.phase(state)
        let cooldown = RuntimePhaseFormatter.cooldownRemainingSeconds(state)
        guard phase != .idle || cooldown > 0 else { return [] }
        var lines = ["Current Step: \(RuntimePhaseFormatter.message(state))"]
        if let elapsed = RuntimePhaseFormatter.elapsedSeconds(state) { lines.append("Elapsed: \(elapsed)s") }
        if let remaining = RuntimePhaseFormatter.deadlineRemainingSeconds(state) { lines.append("Timeout: \(remaining)s") }
        if cooldown > 0 { lines.append("Enable available in: \(cooldown)s") }
        if phase == .restorePaused {
            lines.append("The virtual display will stay active until a physical display is available.")
        }
        return lines
    }

    func autoRollbackText(for state: RuntimeState) -> String {
        guard let deadline = state.rollbackDeadline else { return "Auto rollback: Pending" }
        return "Auto rollback in: \(max(0, Int(ceil(deadline.timeIntervalSinceNow))))s"
    }
}
