import Foundation

public struct MenuActionAvailability: Equatable {
    public var canEnable: Bool
    public var canConfirm: Bool
    public var canRestore: Bool
    public var canToggleKeepAwake: Bool
    public var canQuit: Bool

    public static func make(state: RuntimeState, configHealthy: Bool, operationBusy: Bool, cleanNormal: Bool? = nil) -> MenuActionAvailability {
        let clean = cleanNormal ?? (state.mode == .normal && !state.keepAwake && !state.virtualDisplayCreated)
        return MenuActionAvailability(
            canEnable: clean && configHealthy && !operationBusy,
            canConfirm: state.mode == .confirmRequired && !operationBusy,
            canRestore: !operationBusy,
            canToggleKeepAwake: state.mode == .normal && !operationBusy,
            canQuit: state.mode == .normal && !state.keepAwake && !operationBusy
        )
    }
}

public struct MenuDynamicPresentation: Equatable {
    public var showsConfirmationActions: Bool
    public var showsSettings: Bool
    public var showsOperationBusy: Bool
    public var showsReplacement: Bool
    public var rollbackRemainingSeconds: Int?

    public static func make(state: RuntimeState, operationBusy: Bool, now: Date) -> Self {
        let confirming = state.mode == .confirmRequired
        return MenuDynamicPresentation(
            showsConfirmationActions: confirming,
            showsSettings: state.mode == .normal && !operationBusy,
            showsOperationBusy: operationBusy,
            showsReplacement: state.replacementDisplayType != nil,
            rollbackRemainingSeconds: state.rollbackDeadline.map { max(0, Int(ceil($0.timeIntervalSince(now)))) }
        )
    }
}
