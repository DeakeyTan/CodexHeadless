import XCTest
@testable import CodexHeadlessCore

final class LoggerProcessBoundaryTests: XCTestCase {
    func testConcurrentProcessesWriteOnlyCompletePrefixedLines() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logFile = directory.appendingPathComponent("process.log")
        let helper = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("CodexHeadlessTestHelper")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: helper.path), helper.path)
        let child = Process()
        child.executableURL = helper
        child.arguments = [
            "logger-write", "--path", logFile.path, "--level", "error",
            "--prefix", "child-line", "--count", "100"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment[DiagnosticLoggingPolicy.environmentKey] = "1"
        child.environment = environment
        let childError = Pipe()
        child.standardError = childError
        try child.run()

        let logger = CHLogger(logFile: logFile, policy: DiagnosticLoggingPolicy(enabled: true))
        for index in 0..<100 { logger.info("parent-line-\(index)") }
        child.waitUntilExit()
        let errorText = String(data: childError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(child.terminationReason, .exit)
        XCTAssertEqual(child.terminationStatus, 0, errorText)

        let lines = try String(contentsOf: logFile, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 200)
        XCTAssertTrue(lines.allSatisfy { line in
            line.hasPrefix("[") && (line.contains("] [INFO] ") || line.contains("] [ERROR] "))
        })
        XCTAssertFalse(lines.contains { !$0.contains("parent-line-") && !$0.contains("child-line-") })
    }
}
