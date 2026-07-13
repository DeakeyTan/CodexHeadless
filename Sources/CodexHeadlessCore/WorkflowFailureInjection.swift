import Foundation

public enum EnableFailurePoint: String, CaseIterable {
    case initialPreparingState
    case keepAwakeStarted
    case virtualHostCreated
    case virtualDisplayConfirmed
    case replacementReady
    case replacementPromoted
    case softDisconnectSucceeded
    case brightnessDimmed
    case touchBarHidden
    case finalHeadlessCommit
}

public protocol WorkflowFailureInjecting: AnyObject {
    func check(_ point: EnableFailurePoint) throws
}

public final class NoopWorkflowFailureInjector: WorkflowFailureInjecting {
    public init() {}
    public func check(_ point: EnableFailurePoint) throws {}
}
