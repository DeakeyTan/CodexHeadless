import Foundation
import XCTest
@testable import CodexHeadlessCore

final class LoggerConfigurationTests: XCTestCase {
    func testDefaultMissingAndInvalidLoggingConfigurationRemainDisabled() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = configManager(root)
        XCTAssertFalse(manager.load().effectiveDiagnosticLoggingEnabled)

        var legacy = AppConfig.default
        legacy.diagnosticLoggingEnabled = nil
        try manager.save(legacy)
        XCTAssertFalse(manager.load().effectiveDiagnosticLoggingEnabled)

        let configURL = root.appendingPathComponent("config.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        object["diagnosticLoggingEnabled"] = "not-a-boolean"
        try JSONSerialization.data(withJSONObject: object).write(to: configURL, options: .atomic)
        XCTAssertFalse(manager.load().effectiveDiagnosticLoggingEnabled)
        XCTAssertFalse(manager.health().isHealthy)
    }

    func testDisabledLoggerCreatesNoFileLockOrRotationForEveryLevel() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("nested/CodexHeadless.log")
        let logger = CHLogger(logFile: log, policy: DiagnosticLoggingPolicy(enabled: false))
        logger.info("info")
        logger.warn("warn")
        logger.error("error")
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path + ".lock"))

        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let historical = Data(repeating: 65, count: 5 * 1024 * 1024 + 1)
        try historical.write(to: log)
        logger.error("must remain disabled")
        XCTAssertEqual(try Data(contentsOf: log), historical)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path + ".1"))
    }

    func testRuntimeEnableAndDisableTakeEffectImmediatelyWithoutDeletingHistory() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("CodexHeadless.log")
        let policy = DiagnosticLoggingPolicy(enabled: false)
        let logger = CHLogger(logFile: log, policy: policy)
        logger.info("before")
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
        policy.setEnabled(true)
        logger.info("enabled")
        let enabledContents = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(enabledContents.contains("enabled"))
        policy.setEnabled(false)
        logger.error("after")
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), enabledContents)
    }

    func testDisableWaitsForInFlightWriteAndBlocksLaterConcurrentWrites() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("CodexHeadless.log")
        let policy = DiagnosticLoggingPolicy(enabled: true)
        let logger = CHLogger(logFile: log, policy: policy)
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            started.signal()
            for index in 0..<1_000 { logger.info("concurrent-\(index)") }
            finished.signal()
        }
        started.wait()
        policy.setEnabled(false)
        let contentsAtDisable = (try? Data(contentsOf: log)) ?? Data()
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual((try? Data(contentsOf: log)) ?? Data(), contentsAtDisable)
    }

    func testConfigMutationPersistsLoggingChoice() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = configManager(root)
        try manager.setDiagnosticLoggingEnabled(true)
        XCTAssertTrue(manager.load().effectiveDiagnosticLoggingEnabled)
        try manager.setDiagnosticLoggingEnabled(false)
        XCTAssertFalse(manager.load().effectiveDiagnosticLoggingEnabled)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CodexHeadless-logging-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func configManager(_ root: URL) -> ConfigManager {
        ConfigManager(
            configFile: root.appendingPathComponent("config.json"),
            lockFile: root.appendingPathComponent("config.lock"),
            healthFile: root.appendingPathComponent("config.health.json"),
            enforceMutationSafety: false
        )
    }
}
