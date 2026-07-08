import Foundation
import CoreGraphics
import Darwin
import ObjectiveC.runtime

public struct VirtualDisplayProbeReport {
    public var coreGraphicsLoaded: Bool
    public var cgVirtualDisplayClassAvailable: Bool
    public var descriptorClassAvailable: Bool
    public var modeClassAvailable: Bool
    public var settingsClassAvailable: Bool
    public var sdkHeaderAvailable: Bool

    public var text: String {
        """
        CodexHeadless Virtual Display Probe
        -----------------------------------
        CoreGraphics Loaded: \(coreGraphicsLoaded ? "Yes" : "No")
        CGVirtualDisplay Runtime Class: \(cgVirtualDisplayClassAvailable ? "Available" : "Missing")
        CGVirtualDisplayDescriptor Runtime Class: \(descriptorClassAvailable ? "Available" : "Missing")
        CGVirtualDisplayMode Runtime Class: \(modeClassAvailable ? "Available" : "Missing")
        CGVirtualDisplaySettings Runtime Class: \(settingsClassAvailable ? "Available" : "Missing")
        SDK Header Support: \(sdkHeaderAvailable ? "Available" : "Missing in current Command Line Tools SDK")

        Result: \(cgVirtualDisplayClassAvailable && descriptorClassAvailable ? "Software virtual display host can be explored." : "Software virtual display API is not available in this runtime/SDK path.")
        """
    }
}

public final class VirtualDisplayManager {
    private let logger: CHLogger
    private let stateStore: StateStore

    public init(
        logger: CHLogger = CHLogger(),
        stateStore: StateStore = StateStore()
    ) {
        self.logger = logger
        self.stateStore = stateStore
    }

    public func validateResolution(_ resolution: Resolution) throws {
        try ResolutionManager.validate(resolution)
    }

    public func probe() -> VirtualDisplayProbeReport {
        VirtualDisplayProbeReport(
            coreGraphicsLoaded: true,
            cgVirtualDisplayClassAvailable: NSClassFromString("CGVirtualDisplay") != nil,
            descriptorClassAvailable: NSClassFromString("CGVirtualDisplayDescriptor") != nil,
            modeClassAvailable: NSClassFromString("CGVirtualDisplayMode") != nil,
            settingsClassAvailable: NSClassFromString("CGVirtualDisplaySettings") != nil,
            sdkHeaderAvailable: false
        )
    }

    public func createVirtualDisplay(
        resolution: Resolution,
        refreshRate: Int = 60,
        scaleMode: String = "standard",
        waitTimeoutSeconds: TimeInterval = 5
    ) throws -> UInt32? {
        try validateResolution(resolution)
        reconcileManagedVirtualDisplayIfNeeded()
        if let existingID = activeManagedVirtualDisplayID() {
            logger.info("Managed software virtual display already running: \(existingID).")
            return existingID
        }

        guard let helperPath = HelperExecutableResolver.resolveCodexHeadless() else {
            logger.warn("No codex-headless helper executable was available for virtual display host.")
            return nil
        }

        let beforeIDs = Set(DisplayManager().displays().map(\.id))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = [
            "__virtual-display-host",
            String(resolution.width),
            String(resolution.height),
            String(refreshRate),
            scaleMode
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = PipeTextCollector()
        let errorCollector = PipeTextCollector()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            outputCollector.append(data)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            errorCollector.append(data)
        }
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()

        let pid = process.processIdentifier
        logger.info("Started virtual display host PID \(pid).")

        stateStore.update { state in
            state.virtualDisplayCreated = true
            state.virtualDisplayPID = pid
            state.virtualDisplayRequestedResolution = resolution
            state.virtualDisplayRefreshRate = refreshRate
            state.virtualDisplayScaleMode = scaleMode
        }

        let displayID = waitForNewDisplayID(
            beforeIDs: beforeIDs,
            timeoutSeconds: waitTimeoutSeconds,
            outputCollector: outputCollector
        )
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        guard let displayID else {
            if processIsRunning(pid) {
                kill(pid, SIGTERM)
                waitForProcessExit(process, timeoutSeconds: 0.8)
            }
            logger.warn("Virtual display host did not create a visible display. \(processDiagnostics(process: process, stdout: outputCollector.snapshot(), stderr: errorCollector.snapshot()))")
            stateStore.update { state in
                state.virtualDisplayCreated = false
                state.virtualDisplayPID = nil
                state.virtualDisplayID = nil
                state.virtualDisplayRequestedResolution = nil
                state.virtualDisplayRefreshRate = nil
                state.virtualDisplayScaleMode = nil
            }
            return nil
        }

        stateStore.update { state in
            state.virtualDisplayCreated = true
            state.virtualDisplayPID = pid
            state.virtualDisplayID = displayID
            state.virtualDisplayRequestedResolution = resolution
            state.virtualDisplayRefreshRate = refreshRate
            state.virtualDisplayScaleMode = scaleMode
        }

        logger.info("Software virtual display created: displayID=\(displayID), PID=\(pid), resolution=\(resolution), scaleMode=\(scaleMode).")
        return displayID
    }

    public func reconcileManagedVirtualDisplayIfNeeded() {
        let state = stateStore.load()
        guard state.virtualDisplayCreated,
              let pid = state.virtualDisplayPID,
              processIsRunning(pid) else {
            return
        }

        if let displayID = state.virtualDisplayID,
           DisplayManager().display(id: displayID) != nil {
            return
        }

        guard let display = DisplayManager().managedVirtualDisplay() else {
            return
        }

        stateStore.update { newState in
            newState.virtualDisplayID = display.id
        }
        logger.info("Managed software virtual display reconciled: displayID=\(display.id), PID=\(pid).")
    }

    public func destroyVirtualDisplayIfManaged() {
        let state = stateStore.load()
        var stoppedPIDs = Set<Int32>()

        if let pid = state.virtualDisplayPID {
            if processIsRunning(pid) {
                kill(pid, SIGTERM)
                waitForProcessExit(pid: pid, timeoutSeconds: 0.8)
                logger.info("Stopped managed virtual display host PID \(pid).")
            }
            stoppedPIDs.insert(pid)
        } else {
            logger.info("No managed software virtual display PID in state.")
        }

        for pid in virtualDisplayHostProcessIDs().filter({ !stoppedPIDs.contains($0) }) {
            if processIsRunning(pid) {
                kill(pid, SIGTERM)
                waitForProcessExit(pid: pid, timeoutSeconds: 0.8)
                logger.info("Stopped orphan virtual display host PID \(pid).")
            }
        }

        stateStore.update { newState in
            newState.virtualDisplayCreated = false
            newState.virtualDisplayPID = nil
            newState.virtualDisplayID = nil
            newState.virtualDisplayRequestedResolution = nil
            newState.virtualDisplayRefreshRate = nil
            newState.virtualDisplayScaleMode = nil
        }
    }

    private func activeManagedVirtualDisplayID() -> UInt32? {
        let state = stateStore.load()
        guard let pid = state.virtualDisplayPID,
              processIsRunning(pid),
              let displayID = state.virtualDisplayID,
              DisplayManager().displays().contains(where: { $0.id == displayID }) else {
            return nil
        }
        return displayID
    }

    private func waitForNewDisplayID(
        beforeIDs: Set<UInt32>,
        timeoutSeconds: TimeInterval,
        outputCollector: PipeTextCollector
    ) -> UInt32? {
        let displayManager = DisplayManager()
        var deadline = Date().addingTimeInterval(timeoutSeconds)
        var reportedDisplayID: UInt32?
        while Date() < deadline {
            let displays = displayManager.displays()
            if let display = displayManager.managedVirtualDisplay() {
                return display.id
            }
            if let display = displays.first(where: { !beforeIDs.contains($0.id) && !$0.isBuiltIn }) {
                return display.id
            }
            if let stdoutDisplayID = outputCollector.displayID() {
                if displays.contains(where: { $0.id == stdoutDisplayID && !$0.isBuiltIn }) {
                    return stdoutDisplayID
                }
                if let display = displayManager.display(id: stdoutDisplayID),
                   !display.isBuiltIn {
                    logger.info("Virtual display host reported displayID=\(stdoutDisplayID); direct CoreGraphics lookup is usable.")
                    return stdoutDisplayID
                }

                if reportedDisplayID != stdoutDisplayID {
                    reportedDisplayID = stdoutDisplayID
                    let extendedDeadline = Date().addingTimeInterval(20)
                    if deadline < extendedDeadline {
                        deadline = extendedDeadline
                    }
                    logger.info("Virtual display host reported displayID=\(stdoutDisplayID); waiting for CoreGraphics display enumeration.")
                }
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return nil
    }

    private func waitForProcessExit(_ process: Process, timeoutSeconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func waitForProcessExit(pid: Int32, timeoutSeconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while processIsRunning(pid) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func processDiagnostics(process: Process, stdout: String, stderr: String) -> String {
        let termination: String
        if process.isRunning {
            termination = "running"
        } else {
            termination = "\(process.terminationReason == .exit ? "exit" : "signal"):\(process.terminationStatus)"
        }

        let stdoutText = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrText = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "termination=\(termination), stdout=\(stdoutText.isEmpty ? "<empty>" : stdoutText), stderr=\(stderrText.isEmpty ? "<empty>" : stderrText)"
    }

    private func processIsRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    private func virtualDisplayHostProcessIDs() -> [Int32] {
        do {
            let result = try Shell.run("/bin/ps", ["-axo", "pid=,command="], timeoutSeconds: 2)
            return result.output
                .split(separator: "\n")
                .compactMap { line -> Int32? in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let firstSpace = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                        return nil
                    }
                    let pidText = trimmed[..<firstSpace]
                    let command = trimmed[firstSpace...]
                    guard let pid = Int32(pidText),
                          pid != getpid(),
                          command.contains("__virtual-display-host"),
                          command.contains("codex-headless") || command.contains("CodexHeadless") else {
                        return nil
                    }
                    return pid
                }
        } catch {
            logger.warn("Unable to enumerate orphan virtual display host processes: \(error.localizedDescription)")
            return []
        }
    }
}

private final class PipeTextCollector {
    private let lock = NSLock()
    private var text = ""

    func append(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else {
            return
        }
        lock.lock()
        text += chunk
        lock.unlock()
    }

    func displayID() -> UInt32? {
        let snapshot = snapshot()

        guard let range = snapshot.range(of: #"displayID=(\d+)"#, options: .regularExpression) else {
            return nil
        }

        let match = snapshot[range]
        guard let value = match.split(separator: "=").last else {
            return nil
        }
        return UInt32(value)
    }

    func snapshot() -> String {
        lock.lock()
        let snapshot = text
        lock.unlock()
        return snapshot
    }
}

public enum VirtualDisplayHost {
    private typealias AllocFunction = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?
    private typealias InitWithDescriptorFunction = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
    private typealias InitModeFunction = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> Unmanaged<AnyObject>?
    private typealias ApplySettingsFunction = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
    private typealias DisplayIDFunction = @convention(c) (AnyObject, Selector) -> UInt32

    public static func run(resolution: Resolution, refreshRate: Int, scaleMode: String) throws -> Never {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay"),
              let modeClass = NSClassFromString("CGVirtualDisplayMode"),
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type else {
            throw NSError(domain: "CodexHeadless.VirtualDisplay", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "CGVirtualDisplay runtime classes are unavailable."
            ])
        }

        let descriptor = descriptorClass.init()
        descriptor.setValue("CodexHeadless Virtual Display", forKey: "name")
        descriptor.setValue(NSNumber(value: UInt32(0xC0DE)), forKey: "vendorID")
        descriptor.setValue(NSNumber(value: UInt32(0x0511)), forKey: "productID")
        descriptor.setValue(NSNumber(value: UInt32(1)), forKey: "serialNum")
        descriptor.setValue(NSNumber(value: UInt32(resolution.width)), forKey: "maxPixelsWide")
        descriptor.setValue(NSNumber(value: UInt32(resolution.height)), forKey: "maxPixelsHigh")
        descriptor.setValue(NSValue(size: CGSize(width: 300, height: 170)), forKey: "sizeInMillimeters")

        guard let displayAllocated = allocObject(displayClass)?.takeRetainedValue() else {
            throw NSError(domain: "CodexHeadless.VirtualDisplay", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to allocate CGVirtualDisplay."
            ])
        }
        guard let display = initWithDescriptor(displayAllocated, descriptor: descriptor)?.takeRetainedValue() else {
            throw NSError(domain: "CodexHeadless.VirtualDisplay", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to initialize CGVirtualDisplay."
            ])
        }

        guard let modeAllocated = allocObject(modeClass)?.takeRetainedValue() else {
            throw NSError(domain: "CodexHeadless.VirtualDisplay", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to allocate CGVirtualDisplayMode."
            ])
        }
        guard let mode = initMode(
            modeAllocated,
            width: UInt32(resolution.width),
            height: UInt32(resolution.height),
            refreshRate: Double(refreshRate)
        )?.takeRetainedValue() else {
            throw NSError(domain: "CodexHeadless.VirtualDisplay", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to initialize CGVirtualDisplayMode."
            ])
        }

        let settings = settingsClass.init()
        settings.setValue([mode], forKey: "modes")
        let hiDPI = scaleMode.lowercased() == "hidpi" ? UInt32(1) : UInt32(0)
        settings.setValue(NSNumber(value: hiDPI), forKey: "hiDPI")
        settings.setValue(NSNumber(value: UInt32(0)), forKey: "rotation")

        guard applySettings(display, settings: settings) else {
            throw NSError(domain: "CodexHeadless.VirtualDisplay", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Failed to apply CGVirtualDisplay settings."
            ])
        }

        let displayID = getDisplayID(display)
        print("displayID=\(displayID)")
        fflush(stdout)

        signal(SIGTERM) { _ in exit(0) }
        signal(SIGINT) { _ in exit(0) }
        RunLoop.current.run()
        fatalError("RunLoop unexpectedly returned.")
    }

    private static func objcMsgSendSymbol() -> UnsafeMutableRawPointer {
        dlsym(dlopen(nil, RTLD_LAZY), "objc_msgSend")
    }

    private static func allocObject(_ cls: AnyClass) -> Unmanaged<AnyObject>? {
        let function = unsafeBitCast(objcMsgSendSymbol(), to: AllocFunction.self)
        return function(cls, NSSelectorFromString("alloc"))
    }

    private static func initWithDescriptor(_ object: AnyObject, descriptor: AnyObject) -> Unmanaged<AnyObject>? {
        let function = unsafeBitCast(objcMsgSendSymbol(), to: InitWithDescriptorFunction.self)
        return function(object, NSSelectorFromString("initWithDescriptor:"), descriptor)
    }

    private static func initMode(_ object: AnyObject, width: UInt32, height: UInt32, refreshRate: Double) -> Unmanaged<AnyObject>? {
        let function = unsafeBitCast(objcMsgSendSymbol(), to: InitModeFunction.self)
        return function(object, NSSelectorFromString("initWithWidth:height:refreshRate:"), width, height, refreshRate)
    }

    private static func applySettings(_ display: AnyObject, settings: AnyObject) -> Bool {
        let function = unsafeBitCast(objcMsgSendSymbol(), to: ApplySettingsFunction.self)
        return function(display, NSSelectorFromString("applySettings:"), settings)
    }

    private static func getDisplayID(_ display: AnyObject) -> UInt32 {
        let function = unsafeBitCast(objcMsgSendSymbol(), to: DisplayIDFunction.self)
        return function(display, NSSelectorFromString("displayID"))
    }
}
