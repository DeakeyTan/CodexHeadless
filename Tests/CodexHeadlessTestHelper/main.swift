import CodexHeadlessCore
import Foundation

enum TestHelperError: Error, LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        "Usage: CodexHeadlessTestHelper logger-write --path PATH --level info|error --prefix PREFIX --count COUNT"
    }
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "lock-attempt", let path = option("--path", in: arguments) {
        do {
            let lease = try WorkflowOperationLock(lockFile: URL(fileURLWithPath: path)).acquire(name: "concurrent", timeoutSeconds: 0.2, logLifecycle: false)
            lease.release()
            print("lock=acquired")
            exit(0)
        } catch {
            print("lock=blocked")
            exit(2)
        }
    }
    guard arguments.first == "logger-write",
          let path = option("--path", in: arguments),
          let level = option("--level", in: arguments),
          let prefix = option("--prefix", in: arguments),
          let countText = option("--count", in: arguments),
          let count = Int(countText), count >= 0,
          level == "info" || level == "error" else {
        throw TestHelperError.invalidArguments
    }

    let logger = CHLogger(logFile: URL(fileURLWithPath: path))
    for index in 0..<count {
        if level == "info" {
            logger.info("\(prefix)-\(index)")
        } else {
            logger.error("\(prefix)-\(index)")
        }
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(64)
}
