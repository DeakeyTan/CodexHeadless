import Foundation

public final class ConfirmDialogRestoreSuppression {
    private let lock = NSLock()
    private var suppressed = false

    public init() {}

    public func beginRestore() {
        lock.lock(); suppressed = true; lock.unlock()
    }

    public func clear() {
        lock.lock(); suppressed = false; lock.unlock()
    }

    public func shouldPresent(runtimeMode: HeadlessMode) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return runtimeMode == .confirmRequired && !suppressed
    }
}
