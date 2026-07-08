import Darwin
import Dispatch
import Foundation

public struct ShellResult {
    public var exitCode: Int32
    public var terminationReason: Process.TerminationReason
    public var output: String
    public var errorOutput: String

    public var succeeded: Bool {
        terminationReason == .exit && exitCode == 0
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
        var didFinish = false
        process.terminationHandler = { _ in
            didFinish = true
            finished.signal()
        }

        try process.run()
        if let timeoutSeconds {
            if finished.wait(timeout: .now() + timeoutSeconds) == .timedOut {
                process.terminate()
                if finished.wait(timeout: .now() + 0.2) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 1.0)
                }
            }
        } else {
            process.waitUntilExit()
            didFinish = true
        }

        guard didFinish || !process.isRunning else {
            return ShellResult(
                exitCode: SIGKILL,
                terminationReason: .uncaughtSignal,
                output: "",
                errorOutput: "Process timed out and did not exit after SIGKILL."
            )
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return ShellResult(
            exitCode: process.terminationStatus,
            terminationReason: process.terminationReason,
            output: output,
            errorOutput: errorOutput
        )
    }
}
