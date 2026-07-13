import Foundation

public final class RollbackStateStore {
    private let stateStore: RuntimeStateStoring
    private let logger: CHLogger

    public init(stateStore: RuntimeStateStoring = StateStore(), logger: CHLogger = CHLogger()) {
        self.stateStore = stateStore
        self.logger = logger
    }

    public func cancel() throws {
        try stateStore.transaction { state in
            state.rollbackConfirmed = true
            state.rollbackDeadline = nil
        }
        logger.info("Rollback guard cancelled.")
    }
}
