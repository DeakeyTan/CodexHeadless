import Foundation

public final class RollbackGuard {
    private let stateStore: StateStore
    private let logger: CHLogger

    public init(stateStore: StateStore = StateStore(), logger: CHLogger = CHLogger()) {
        self.stateStore = stateStore
        self.logger = logger
    }

    public func begin(timeoutSeconds: Int) -> Date {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        stateStore.update { state in
            state.rollbackDeadline = deadline
            state.rollbackConfirmed = false
        }
        logger.info("Rollback guard started. Deadline: \(deadline).")
        return deadline
    }

    public func confirm() {
        stateStore.update { state in
            state.rollbackConfirmed = true
            state.rollbackDeadline = nil
            if state.mode == .confirmRequired {
                let displayReady = state.virtualDisplayCreated || state.externalDisplayPromoted == true
                let builtInHandled = state.builtInBrightnessDimmed == true || state.builtInSoftDisconnected == true
                state.mode = displayReady && builtInHandled ? .headless : .fallback
            }
        }
        logger.info("Rollback guard confirmed.")
    }

    public func cancel() {
        stateStore.update { state in
            state.rollbackConfirmed = true
            state.rollbackDeadline = nil
        }
        logger.info("Rollback guard cancelled.")
    }

    public func needsRollback(now: Date = Date()) -> Bool {
        let state = stateStore.load()
        guard !state.rollbackConfirmed, let deadline = state.rollbackDeadline else {
            return false
        }
        return now >= deadline
    }
}
