import Darwin
import Foundation

public final class WorkflowOperationLease: WorkflowOperationLeaseHandling {
    public let operationID: String
    public let name: String

    private let descriptor: Int32
    private let logger: CHLogger
    private let logLifecycle: Bool
    private var released = false

    fileprivate init(descriptor: Int32, operationID: String, name: String, logger: CHLogger, logLifecycle: Bool) {
        self.descriptor = descriptor
        self.operationID = operationID
        self.name = name
        self.logger = logger
        self.logLifecycle = logLifecycle
        if logLifecycle {
            logger.info("[Operation \(operationID)] started: \(name)")
        }
    }

    public func release() {
        guard !released else { return }
        released = true
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
        if logLifecycle {
            logger.info("[Operation \(operationID)] finished: \(name)")
        }
    }

    deinit {
        release()
    }
}

public final class WorkflowOperationLock: WorkflowOperationLocking {
    private let lockFile: URL
    private let logger: CHLogger
    private let clock: WorkflowClock

    public init(
        lockFile: URL = CodexHeadlessPaths.operationLockFile,
        logger: CHLogger = CHLogger(),
        clock: WorkflowClock = SystemWorkflowClock()
    ) {
        self.lockFile = lockFile
        self.logger = logger
        self.clock = clock
    }

    public func acquire(
        name: String,
        timeoutSeconds: TimeInterval = 60,
        logLifecycle: Bool = true
    ) throws -> WorkflowOperationLeaseHandling {
        try FileManager.default.createDirectory(
            at: lockFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = Darwin.open(lockFile.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw StateStoreError.lockOpenFailed(path: lockFile.path, errno: errno)
        }

        let deadline = clock.uptime + timeoutSeconds
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else {
                _ = Darwin.close(descriptor)
                throw StateStoreError.lockOpenFailed(path: lockFile.path, errno: errno)
            }
            guard clock.uptime < deadline else {
                _ = Darwin.close(descriptor)
                throw StateStoreError.lockTimeout(path: lockFile.path, timeoutSeconds: timeoutSeconds)
            }
            clock.sleep(seconds: 0.05)
        }

        let operationID = String(UUID().uuidString.prefix(8)).lowercased()
        return WorkflowOperationLease(
            descriptor: descriptor,
            operationID: operationID,
            name: name,
            logger: logger,
            logLifecycle: logLifecycle
        )
    }
}
