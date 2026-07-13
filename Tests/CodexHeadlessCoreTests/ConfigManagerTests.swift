import Foundation
import XCTest
@testable import CodexHeadlessCore

final class ConfigManagerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHeadless-ConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLegacyConfirmationMigratesOnceAndPreservesValues() throws {
        let manager = makeManager()
        let legacy = """
        {
          "startAtLogin": false,
          "virtualDisplay": {"enabled": true, "resolution": {"width": 2560, "height": 1440}, "refreshRate": 60, "scaleMode": "hidpi"},
          "rollback": {"enabled": true, "timeoutSeconds": 30},
          "confirmDialog": {"enabled": false, "timeoutSeconds": 45, "showHotkeyHints": false, "showCountdown": true}
        }
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("config.json"))

        let config = manager.load()
        XCTAssertEqual(config.schemaVersion, 2)
        XCTAssertEqual(config.effectiveConfirmation.timeoutSeconds, 45)
        XCTAssertFalse(config.effectiveConfirmation.dialogEnabled)
        XCTAssertEqual(config.effectiveConfirmation.showHotkeyHints, false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.v1.backup.json").path))
        let migratedJSON = try String(contentsOf: directory.appendingPathComponent("config.json"), encoding: .utf8)
        XCTAssertFalse(migratedJSON.contains("\"confirmDialog\""))

        _ = manager.load()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0 == "config.v1.backup.json" }.count, 1)
    }

    func testCorruptedConfigUsesSafeDefaultsAndMarksDegraded() throws {
        let manager = makeManager()
        try Data("broken".utf8).write(to: directory.appendingPathComponent("config.json"))
        let config = manager.load()
        XCTAssertFalse(config.softDisconnectBuiltInDisplay ?? true)
        XCTAssertFalse(config.hideTouchBarInHeadless ?? true)
        XCTAssertFalse(manager.health().isHealthy)
        XCTAssertNotNil(manager.health().damagedBackupPath)

        try manager.resetConfigToDefault()
        XCTAssertTrue(manager.health().isHealthy)
    }

    func testTimingValidationAndUnits() throws {
        let manager = makeManager()
        try manager.setTimingValue(key: "restorePhysicalDisplayGraceSeconds", value: 7)
        try manager.setTimingValue(key: "restorePostPromoteStabilizationMilliseconds", value: 750)
        XCTAssertEqual(manager.load().effectiveTiming.restorePhysicalDisplayGraceSeconds, 7)
        XCTAssertEqual(manager.load().effectiveTiming.restorePostPromoteStabilizationMilliseconds, 750)
        XCTAssertThrowsError(try manager.setTimingValue(key: "restorePhysicalDisplayGraceSeconds", value: 121))
    }

    func testFutureSchemaIsNotDowngradedOrOverwritten() throws {
        let manager = makeManager()
        let original = """
        {"schemaVersion":3,"futureField":"preserve-me"}
        """
        let configURL = directory.appendingPathComponent("config.json")
        try Data(original.utf8).write(to: configURL)

        XCTAssertThrowsError(try manager.read()) { error in
            guard case ConfigManagerError.unsupportedFutureSchema(3) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), original)
        XCTAssertFalse(manager.health().isHealthy)
    }

    func testDamagedConfigBackupIsDeduplicated() throws {
        let manager = makeManager()
        try Data("broken".utf8).write(to: directory.appendingPathComponent("config.json"))
        _ = manager.load()
        _ = manager.load()
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("config.damaged.") }
        XCTAssertEqual(backups.count, 1)
    }

    private func makeManager() -> ConfigManager {
        ConfigManager(
            configFile: directory.appendingPathComponent("config.json"),
            lockFile: directory.appendingPathComponent("config.lock"),
            healthFile: directory.appendingPathComponent("config.health.json")
        )
    }
}
