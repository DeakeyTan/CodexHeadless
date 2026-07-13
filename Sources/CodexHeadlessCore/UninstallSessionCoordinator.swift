import Foundation

public final class UninstallSessionCoordinator {
    private let operationLock: WorkflowOperationLocking
    private let safetyChecker: UninstallSafetyChecker
    private let entryPoints: UninstallEntryPointManaging
    private let deleter: UninstallFileDeleting
    private let barrier: UninstallSessionBarrierHandling
    private let logger: CHLogger

    public init(
        operationLock: WorkflowOperationLocking,
        safetyChecker: UninstallSafetyChecker,
        entryPoints: UninstallEntryPointManaging,
        deleter: UninstallFileDeleting,
        barrier: UninstallSessionBarrierHandling,
        logger: CHLogger = CHLogger()
    ) {
        self.operationLock = operationLock
        self.safetyChecker = safetyChecker
        self.entryPoints = entryPoints
        self.deleter = deleter
        self.barrier = barrier
        self.logger = logger
    }

    public func execute(_ request: UninstallSessionRequest) -> UninstallSessionResult {
        let started = DispatchTime.now().uptimeNanoseconds
        logger.info("[Uninstall] session-start")
        do { try UninstallSessionPathPolicy.validate(request) } catch { return .refused(error.localizedDescription) }
        let lease: WorkflowOperationLeaseHandling
        do { lease = try operationLock.acquire(name: "uninstall-session") }
        catch { return .failed("Workflow lock unavailable: \(error.localizedDescription)") }
        defer { lease.release() }
        logger.info("[Uninstall] lock-acquired")

        let preflightStarted = DispatchTime.now().uptimeNanoseconds
        let safety = safetyChecker.checkWhileLockHeld()
        logger.info("[Perf] uninstall-preflight durationMs=\((DispatchTime.now().uptimeNanoseconds - preflightStarted) / 1_000_000)")
        guard safety.status == .safe else {
            return safety.status == .unverified ? .failed(safety.text) : .refused(safety.text)
        }
        logger.info("[Uninstall] safety-preflight=pass")
        do { try barrier.afterPreflight() } catch { return .failed("Uninstall barrier failed: \(error.localizedDescription)") }

        let appExecutable = request.installedAppURL.appendingPathComponent("Contents/MacOS/CodexHeadless")
        if let reason = entryPoints.stopAndVerify(launchAgentURL: request.launchAgentURL, appExecutableURL: appExecutable) {
            return .refused(reason)
        }
        logger.info("[Uninstall] launch-agent-stopped")
        logger.info("[Uninstall] app-stopped")

        do {
            logger.info("[Uninstall] removing-launch-agent")
            try deleter.remove(request.launchAgentURL)
            logger.info("[Uninstall] removing-app")
            try deleter.remove(request.installedAppURL)
        } catch {
            return .failed("Installed CLI was preserved. Deletion failed: \(error.localizedDescription)")
        }
        do {
            logger.info("[Uninstall] removing-cli")
            try deleter.remove(request.installedCLIURL)
        } catch {
            return .failed("The recovery CLI remains at \(request.installedCLIURL.path): \(error.localizedDescription)")
        }
        do { try barrier.deletionCompleted() } catch { return .failed(error.localizedDescription) }
        logger.info("[Uninstall] completed")
        logger.info("[Perf] uninstall-session totalMs=\((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)")
        return .completed
    }
}

public enum LaunchAgentObservation: Equatable {
    case loaded
    case notLoaded
    case unverified(String)
}

public final class SystemUninstallEntryPointManager: UninstallEntryPointManaging {
    private let launchctlPrint: (String) throws -> ShellResult

    public init(launchctlPrint: @escaping (String) throws -> ShellResult = { service in
        try Shell.run("/bin/launchctl", ["print", service], timeoutSeconds: 2)
    }) {
        self.launchctlPrint = launchctlPrint
    }

    public func stopAndVerify(launchAgentURL: URL, appExecutableURL: URL) -> String? {
        let service = "gui/\(getuid())/com.codexheadless.app"
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            _ = try? Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentURL.path], timeoutSeconds: 5)
        }
        switch observeLaunchAgent(service: service) {
        case .loaded:
            return "The CodexHeadless LaunchAgent is still loaded."
        case .unverified(let reason):
            return "The CodexHeadless LaunchAgent shutdown could not be verified: \(reason)"
        case .notLoaded:
            break
        }
        _ = try? Shell.run("/usr/bin/osascript", ["-e", "tell application id \"com.codexheadless.app\" to quit"], timeoutSeconds: 5)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !isExactExecutableRunning(appExecutableURL.path) { return nil }
            usleep(100_000)
        }
        return isExactExecutableRunning(appExecutableURL.path) ? "The CodexHeadless App is still running." : nil
    }

    func observeLaunchAgent(service: String) -> LaunchAgentObservation {
        do { return Self.classifyLaunchAgentPrint(try launchctlPrint(service)) }
        catch { return .unverified("launchctl could not be executed: \(error.localizedDescription)") }
    }

    static func classifyLaunchAgentPrint(_ result: ShellResult) -> LaunchAgentObservation {
        if result.timedOut { return .unverified("launchctl print timed out") }
        guard result.terminationReason == .exit else {
            return .unverified("launchctl print terminated by \(result.terminationDescription)")
        }
        if result.exitCode == 0 { return .loaded }
        let output = (result.output + "\n" + result.errorOutput).lowercased()
        if output.contains("could not find service") || output.contains("service not found") {
            return .notLoaded
        }
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return .unverified(detail.isEmpty ? "launchctl print returned exit \(result.exitCode) without a recognized result" : detail)
    }

    private func isExactExecutableRunning(_ path: String) -> Bool {
        guard let result = try? Shell.run("/bin/ps", ["-axo", "command="], timeoutSeconds: 2), result.succeeded else { return true }
        return result.output.split(separator: "\n").contains { line in
            line.split(whereSeparator: \.isWhitespace).first.map(String.init) == path
        }
    }
}

public final class SystemUninstallFileDeleter: UninstallFileDeleting {
    public init() {}
    public func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch {
            let result = try Shell.run("/usr/bin/sudo", ["/bin/rm", "-rf", url.path], timeoutSeconds: 60)
            guard result.succeeded else { throw error }
        }
    }
}

public final class FileUninstallSessionBarrier: UninstallSessionBarrierHandling {
    private let directory: URL?
    public init(directory: URL?) { self.directory = directory }
    public func afterPreflight() throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("ready".utf8).write(to: directory.appendingPathComponent("lock-acquired"), options: .atomic)
        let continuation = directory.appendingPathComponent("continue")
        while !FileManager.default.fileExists(atPath: continuation.path) { usleep(10_000) }
    }
    public func deletionCompleted() throws {
        guard let directory else { return }
        try Data("done".utf8).write(to: directory.appendingPathComponent("deletion-complete"), options: .atomic)
    }
}
