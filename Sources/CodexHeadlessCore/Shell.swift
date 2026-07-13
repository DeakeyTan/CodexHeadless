import Darwin
import Dispatch
import Foundation

public struct ShellResult {
    public var exitCode: Int32
    public var terminationReason: Process.TerminationReason
    public var output: String
    public var errorOutput: String
    public var timedOut: Bool
    public var durationMilliseconds: Int

    public var succeeded: Bool {
        !timedOut && terminationReason == .exit && exitCode == 0
    }

    public var terminationDescription: String {
        switch terminationReason {
        case .exit:
            return "exit"
        case .uncaughtSignal:
            return "uncaught signal"
        @unknown default:
            return "unknown"
        }
    }

    public func wasUncaughtSignal(_ signal: Int32) -> Bool {
        terminationReason == .uncaughtSignal && exitCode == signal
    }
}

public enum Shell {
    @discardableResult
    public static func run(
        _ executable: String,
        _ arguments: [String] = [],
        timeoutSeconds: TimeInterval? = nil
    ) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        let started = DispatchTime.now().uptimeNanoseconds
        try process.run()
        let outputReader = ShellPipeReader(handle: outputPipe.fileHandleForReading)
        let errorReader = ShellPipeReader(handle: errorPipe.fileHandleForReading)
        outputReader.start()
        errorReader.start()
        var timedOut = false
        if let timeoutSeconds {
            if finished.wait(timeout: .now() + timeoutSeconds) == .timedOut {
                timedOut = true
                process.terminate()
                if finished.wait(timeout: .now() + 0.2) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 1.0)
                }
            }
        } else {
            _ = finished.wait(timeout: .distantFuture)
        }

        outputReader.finish(timeoutSeconds: 1)
        errorReader.finish(timeoutSeconds: 1)
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        let durationMilliseconds = Int(elapsed / 1_000_000)

        return ShellResult(
            exitCode: process.isRunning ? SIGKILL : process.terminationStatus,
            terminationReason: process.isRunning ? .uncaughtSignal : process.terminationReason,
            output: outputReader.text,
            errorOutput: process.isRunning
                ? errorReader.text + "Process timed out and did not exit after SIGKILL."
                : errorReader.text,
            timedOut: timedOut || process.isRunning,
            durationMilliseconds: durationMilliseconds
        )
    }
}

private final class ShellPipeReader {
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "CodexHeadless.shell-pipe-reader")
    private let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var data = Data()

    init(handle: FileHandle) { self.handle = handle }

    func start() {
        queue.async { [self] in
            let value = handle.readDataToEndOfFile()
            lock.lock(); data = value; lock.unlock()
            finished.signal()
        }
    }

    func finish(timeoutSeconds: TimeInterval) {
        _ = finished.wait(timeout: .now() + timeoutSeconds)
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
