import Foundation

public protocol WorkflowClock: AnyObject {
    var now: Date { get }
    var uptime: TimeInterval { get }
    func sleep(seconds: TimeInterval)
}

public final class SystemWorkflowClock: WorkflowClock {
    public init() {}
    public var now: Date { Date() }
    public var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
    public func sleep(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        Thread.sleep(forTimeInterval: seconds)
    }
}
