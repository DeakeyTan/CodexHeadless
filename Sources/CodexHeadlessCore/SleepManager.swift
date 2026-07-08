import Darwin
import Foundation
import IOKit.pwr_mgt

public enum KeepAwakeProcessKind {
    case app
    case cli
}

public final class SleepManager {
    private let logger: CHLogger
    private let stateStore: StateStore
    private let configManager: ConfigManager
    private let processKind: KeepAwakeProcessKind
    private var nativeAssertionID: IOPMAssertionID?
    private var sudoPMSetAvailable: Bool?

    public init(
        logger: CHLogger = CHLogger(),
        stateStore: StateStore = StateStore(),
        configManager: ConfigManager = ConfigManager(),
        processKind: KeepAwakeProcessKind = .cli
    ) {
        self.logger = logger
        self.stateStore = stateStore
        self.configManager = configManager
        self.processKind = processKind
    }

    public func enableKeepAwake() throws {
        let requestedBackend = configManager.load().keepAwakeBackend ?? .caffeinate
        let effectiveBackend = effectiveBackend(for: requestedBackend)

        if requestedBackend == .native, effectiveBackend == .caffeinate {
            logger.warn("Native Keep Awake was requested from CLI; falling back to caffeinate because CLI assertions do not persist after process exit.")
        }

        switch effectiveBackend {
        case .native:
            try enableNativeKeepAwake()
        case .caffeinate:
            try enableCaffeinateKeepAwake()
        }

        applyPMSetForKeepAwake()
    }

    private func enableCaffeinateKeepAwake() throws {
        var state = stateStore.load()
        if let pid = state.caffeinatePID, processIsRunning(pid) {
            logger.info("Keep Awake already running with caffeinate PID \(pid).")
        } else {
            let pid = try startCaffeinate()
            state.caffeinatePID = pid
            logger.info("Started caffeinate with PID \(pid).")
        }

        state.keepAwake = true
        state.keepAwakeBackend = KeepAwakeBackend.caffeinate.rawValue
        try stateStore.save(state)
    }

    private func enableNativeKeepAwake() throws {
        var state = stateStore.load()
        if nativeAssertionID == nil {
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "CodexHeadless Keep Awake" as CFString,
                &assertionID
            )

            guard result == kIOReturnSuccess else {
                throw NSError(domain: "CodexHeadless.Sleep", code: Int(result), userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create native Keep Awake power assertion."
                ])
            }

            nativeAssertionID = assertionID
            logger.info("Created native Keep Awake assertion: \(assertionID).")
        } else {
            logger.info("Native Keep Awake assertion already active: \(nativeAssertionID ?? 0).")
        }

        if let pid = state.caffeinatePID, processIsRunning(pid) {
            kill(pid, SIGTERM)
            logger.info("Stopped managed caffeinate PID \(pid) after switching to native Keep Awake.")
        }

        state.keepAwake = true
        state.caffeinatePID = nil
        state.keepAwakeBackend = KeepAwakeBackend.native.rawValue
        try stateStore.save(state)
    }

    public func disableKeepAwake() {
        var state = stateStore.load()
        releaseNativeAssertionIfNeeded()

        if let pid = state.caffeinatePID {
            if processIsRunning(pid) {
                kill(pid, SIGTERM)
                logger.info("Stopped managed caffeinate PID \(pid).")
            }
            state.caffeinatePID = nil
        }

        state.keepAwake = false
        state.keepAwakeBackend = nil
        do {
            try stateStore.save(state)
        } catch {
            logger.error("Failed to save state while disabling Keep Awake: \(error.localizedDescription)")
        }
    }

    public func syncWithState() {
        let state = stateStore.load()
        if !state.keepAwake {
            releaseNativeAssertionIfNeeded()
        }
    }

    public func applyDisplaySleepFast() {
        runSudoPMSet(["-a", "displaysleep", "1"])
    }

    private func effectiveBackend(for backend: KeepAwakeBackend) -> KeepAwakeBackend {
        if backend == .native, processKind == .cli {
            return .caffeinate
        }
        return backend
    }

    private func releaseNativeAssertionIfNeeded() {
        guard let assertionID = nativeAssertionID else {
            return
        }

        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            logger.info("Released native Keep Awake assertion: \(assertionID).")
        } else {
            logger.warn("Failed to release native Keep Awake assertion \(assertionID): \(result).")
        }
        nativeAssertionID = nil
    }

    private func startCaffeinate() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-dimsu"]
        try process.run()
        return process.processIdentifier
    }

    private func applyPMSetForKeepAwake() {
        runSudoPMSet(["-a", "sleep", "0"])
        runSudoPMSet(["-a", "displaysleep", "1"])
        runSudoPMSet(["-a", "disksleep", "0"])
    }

    private func runSudoPMSet(_ arguments: [String]) {
        guard canRunSudoPMSet() else {
            logger.warn("pmset \(arguments.joined(separator: " ")) skipped: sudo credentials are not cached. Run with sudo once or ignore; caffeinate remains active.")
            return
        }

        do {
            let result = try Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + arguments, timeoutSeconds: 0.8)
            if result.succeeded {
                logger.info("pmset \(arguments.joined(separator: " ")) succeeded.")
            } else {
                let errorOutput = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if errorOutput.contains("a password is required") || errorOutput.contains("a terminal is required") {
                    logger.warn("pmset \(arguments.joined(separator: " ")) skipped: sudo credentials are not cached. Run with sudo once or ignore; caffeinate remains active.")
                } else {
                    logger.warn("pmset \(arguments.joined(separator: " ")) failed: \(errorOutput)")
                }
            }
        } catch {
            logger.warn("Unable to run pmset \(arguments.joined(separator: " ")): \(error.localizedDescription)")
        }
    }

    private func canRunSudoPMSet() -> Bool {
        if let sudoPMSetAvailable {
            return sudoPMSetAvailable
        }

        do {
            let result = try Shell.run("/usr/bin/sudo", ["-n", "-v"], timeoutSeconds: 0.5)
            let available = result.succeeded
            sudoPMSetAvailable = available
            if !available {
                logger.warn("pmset changes will be skipped: sudo credentials are not cached.")
            }
            return available
        } catch {
            sudoPMSetAvailable = false
            logger.warn("pmset changes will be skipped: sudo credential check failed: \(error.localizedDescription)")
            return false
        }
    }

    private func processIsRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}
