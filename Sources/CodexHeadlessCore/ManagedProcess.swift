import Darwin
import Foundation

public struct ManagedProcessIdentity: Equatable {
    public var pid: Int32
    public var executablePath: String
    public var requiredCommandFragments: [String]
    public var expectedStartTime: String?
    public var expectedExecutableFileIdentity: String?

    public init(
        pid: Int32,
        executablePath: String,
        requiredCommandFragments: [String],
        expectedStartTime: String? = nil,
        expectedExecutableFileIdentity: String? = nil
    ) {
        self.pid = pid
        self.executablePath = executablePath
        self.requiredCommandFragments = requiredCommandFragments
        self.expectedStartTime = expectedStartTime
        self.expectedExecutableFileIdentity = expectedExecutableFileIdentity
    }

    public func matches(facts observed: ManagedProcessFacts) -> Bool {
        guard observed.pid == pid else { return false }
        let expectedPath = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
        guard observed.executableCanonicalPath == expectedPath,
              requiredCommandFragments.allSatisfy(observed.command.contains) else { return false }
        if let expectedStartTime, observed.processStartTime != expectedStartTime { return false }
        if let expectedExecutableFileIdentity,
           observed.executableFileIdentity != expectedExecutableFileIdentity { return false }
        return true
    }
}

public struct ManagedProcessFacts: Equatable {
    public var pid: Int32
    public var command: String
    public var executableCanonicalPath: String
    public var executableFileIdentity: String?
    public var processStartTime: String?
}

public protocol ManagedProcessInspecting: AnyObject {
    func isRunning(pid: Int32) -> Bool
    func command(pid: Int32) -> String?
    func matches(_ identity: ManagedProcessIdentity) -> Bool
    func terminate(_ identity: ManagedProcessIdentity, timeoutSeconds: TimeInterval) -> ManagedResourceCleanupResult
    func facts(pid: Int32) -> ManagedProcessFacts?
}

public extension ManagedProcessInspecting {
    func facts(pid: Int32) -> ManagedProcessFacts? { nil }

    func ownershipRecord(
        pid: Int32,
        instanceID: String,
        executablePath: String,
        requiredCommandFragments: [String],
        ownerOperationID: String,
        resourceKind: String,
        createdAt: Date
    ) -> ManagedProcessOwnershipRecord {
        let observed = facts(pid: pid)
        return ManagedProcessOwnershipRecord(
            instanceID: instanceID,
            pid: pid,
            executableCanonicalPath: observed?.executableCanonicalPath
                ?? URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path,
            executableFileIdentity: observed?.executableFileIdentity,
            processStartTime: observed?.processStartTime,
            expectedCommandFragments: requiredCommandFragments,
            ownerOperationID: ownerOperationID,
            resourceKind: resourceKind,
            createdAt: createdAt
        )
    }
}

public final class ManagedProcessInspector: ManagedProcessInspecting {
    private let clock: WorkflowClock
    public init(clock: WorkflowClock = SystemWorkflowClock()) { self.clock = clock }

    public func isRunning(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    public func command(pid: Int32) -> String? {
        guard isRunning(pid: pid) else { return nil }
        do {
            let result = try Shell.run("/bin/ps", ["-p", String(pid), "-o", "command="], timeoutSeconds: 2)
            guard result.succeeded else { return nil }
            let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }

    public func matches(_ identity: ManagedProcessIdentity) -> Bool {
        guard let observed = facts(pid: identity.pid) else { return false }
        return identity.matches(facts: observed)
    }

    public func facts(pid: Int32) -> ManagedProcessFacts? {
        guard isRunning(pid: pid), let command = command(pid: pid) else { return nil }
        let executableText: String
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        if pathLength > 0 {
            executableText = String(cString: pathBuffer)
        } else if let executableResult = try? Shell.run(
            "/bin/ps", ["-p", String(pid), "-o", "comm="], timeoutSeconds: 2
        ), executableResult.succeeded {
            executableText = executableResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil
        }
        guard !executableText.isEmpty else { return nil }
        let executable = URL(fileURLWithPath: executableText).resolvingSymlinksInPath().path
        let startTime = (try? Shell.run(
            "/bin/ps", ["-p", String(pid), "-o", "lstart="], timeoutSeconds: 2
        ))?.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return ManagedProcessFacts(
            pid: pid,
            command: command,
            executableCanonicalPath: executable,
            executableFileIdentity: fileIdentity(path: executable),
            processStartTime: startTime?.isEmpty == false ? startTime : nil
        )
    }

    public func terminate(_ identity: ManagedProcessIdentity, timeoutSeconds: TimeInterval) -> ManagedResourceCleanupResult {
        guard isRunning(pid: identity.pid) else { return .alreadyStopped }
        guard matches(identity) else {
            return .ownershipMismatch(reason: "PID \(identity.pid) command does not match the recorded instance.")
        }
        guard kill(identity.pid, SIGTERM) == 0 else {
            return .failed(reason: "SIGTERM failed for PID \(identity.pid), errno=\(errno).")
        }
        let deadline = clock.uptime + timeoutSeconds
        while isRunning(pid: identity.pid), clock.uptime < deadline {
            clock.sleep(seconds: 0.05)
        }
        return isRunning(pid: identity.pid)
            ? .failed(reason: "PID \(identity.pid) did not exit within \(timeoutSeconds)s.")
            : .stopped
    }

    private func fileIdentity(path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let volume = attributes[.systemNumber] as? NSNumber,
              let file = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return "\(volume.uint64Value):\(file.uint64Value)"
    }
}
