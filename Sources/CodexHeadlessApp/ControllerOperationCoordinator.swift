import CodexHeadlessCore
import Foundation

final class ControllerOperationCoordinator {
    private let userQueue = DispatchQueue(label: "CodexHeadless.controller-operation.user", qos: .userInitiated)
    private let maintenanceQueue = DispatchQueue(label: "CodexHeadless.controller-operation.maintenance", qos: .utility)
    private let lock = NSLock()
    private let logger: CHLogger
    private let stateDidChange: () -> Void
    private var busy = false
    private var periodicMaintenanceQueued = false
    private var userGeneration: UInt64 = 0

    var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        return busy
    }

    init(logger: CHLogger, stateDidChange: @escaping () -> Void) {
        self.logger = logger
        self.stateDidChange = stateDidChange
    }

    @discardableResult
    func submit<Value>(
        name: String,
        source: String,
        operation: @escaping () throws -> Value,
        completion: ((Result<Value, Error>) -> Void)? = nil
    ) -> Bool {
        lock.lock()
        guard !busy else {
            lock.unlock()
            logger.warn("[State] \(name) ignored, source=\(source), another controller operation is running")
            return false
        }
        busy = true
        userGeneration &+= 1
        lock.unlock()
        let queuedAt = DispatchTime.now().uptimeNanoseconds
        userQueue.async { [weak self] in
            let startedAt = DispatchTime.now().uptimeNanoseconds
            self?.logger.info("[Perf] \(name) queuedToCoreStartMs=\((startedAt - queuedAt) / 1_000_000)")
            let result = Result { try operation() }
            let coreFinishedAt = DispatchTime.now().uptimeNanoseconds
            DispatchQueue.main.async {
                guard let self else { return }
                self.lock.lock(); self.busy = false; self.lock.unlock()
                let uiAt = DispatchTime.now().uptimeNanoseconds
                self.logger.info("[Perf] \(name) coreFinishToUiMs=\((uiAt - coreFinishedAt) / 1_000_000)")
                completion?(result)
                self.stateDidChange()
            }
        }
        DispatchQueue.main.async { [stateDidChange] in stateDidChange() }
        return true
    }

    func submitPeriodic(_ operation: @escaping () -> Void) {
        lock.lock()
        guard !busy, !periodicMaintenanceQueued else { lock.unlock(); return }
        periodicMaintenanceQueued = true
        let generation = userGeneration
        lock.unlock()
        maintenanceQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let superseded = self.userGeneration != generation || self.busy
            self.lock.unlock()
            guard !superseded else {
                self.lock.lock(); self.periodicMaintenanceQueued = false; self.lock.unlock()
                return
            }
            operation()
            self.lock.lock(); self.periodicMaintenanceQueued = false; self.lock.unlock()
        }
    }
}
