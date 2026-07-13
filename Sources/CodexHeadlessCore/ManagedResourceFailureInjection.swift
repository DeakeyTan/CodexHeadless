import Foundation

public enum ManagedResourceFailurePoint: String, CaseIterable {
    case beforeIntentJournal
    case afterIntentJournal
    case afterProcessStart
    case afterOwnershipObservation
    case afterObservedJournal
    case beforeRuntimeCommit
    case afterRuntimeCommit
    case beforeCleanup
    case afterTerminateRequest
    case afterResourceDisappearCheck
}

public protocol ManagedResourceFailureInjecting: AnyObject {
    func check(_ point: ManagedResourceFailurePoint, resourceKind: String) throws
}

public final class NoopManagedResourceFailureInjector: ManagedResourceFailureInjecting {
    public init() {}
    public func check(_ point: ManagedResourceFailurePoint, resourceKind: String) throws {}
}
