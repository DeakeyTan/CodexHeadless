import Foundation

public enum PeriodicMaintenanceAction: Equatable {
    case refreshCooldown
    case checkRollback
    case resumePausedRestore
    case reconcileManagedResources
    case refreshCleanNormalCache
}

public struct PeriodicMaintenancePolicy {
    public var normalAssessmentInterval: TimeInterval = 30
    public var headlessReconcileInterval: TimeInterval = 10

    public init() {}

    public func actions(
        state: RuntimeState,
        uptime: TimeInterval,
        lastNormalAssessmentUptime: TimeInterval?,
        lastHeadlessReconcileUptime: TimeInterval?
    ) -> [PeriodicMaintenanceAction] {
        switch state.mode {
        case .normal:
            var result: [PeriodicMaintenanceAction] = [.refreshCooldown]
            if lastNormalAssessmentUptime.map({ uptime - $0 >= normalAssessmentInterval }) ?? true {
                result.append(.refreshCleanNormalCache)
            }
            return result
        case .confirmRequired:
            var result: [PeriodicMaintenanceAction] = [.checkRollback]
            if lastHeadlessReconcileUptime.map({ uptime - $0 >= 5 }) ?? true { result.append(.reconcileManagedResources) }
            return result
        case .headless, .fallback:
            if lastHeadlessReconcileUptime.map({ uptime - $0 >= headlessReconcileInterval }) ?? true {
                return [.reconcileManagedResources]
            }
            return []
        case .restoring where state.phase == .restorePaused:
            return [.resumePausedRestore]
        case .preparing, .restoring, .error, .recoveryRequired:
            return []
        }
    }
}
