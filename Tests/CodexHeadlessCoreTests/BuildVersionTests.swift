import XCTest
@testable import CodexHeadlessCore

final class BuildVersionTests: XCTestCase {
    func testDevelopmentFallbackDoesNotClaimUAT() {
        let value = CodexHeadlessVersion.resolve(
            environmentVersion: nil, bundleVersion: nil,
            adjacentVersion: nil, installedVersion: nil
        )
        XCTAssertEqual(value, "0.9.0-dev")
        XCTAssertFalse(value.contains("uat"))
    }

    func testExplicitEnvironmentWinsAndNormalizesTagPrefix() {
        XCTAssertEqual(CodexHeadlessVersion.resolve(
            environmentVersion: "v0.9.0-uat.1", bundleVersion: "0.9.0-dev",
            adjacentVersion: "0.8.0", installedVersion: "0.7.0"
        ), "0.9.0-uat.1")
    }

    func testBundleThenAdjacentThenInstalledResolutionOrder() {
        XCTAssertEqual(CodexHeadlessVersion.resolve(
            environmentVersion: nil, bundleVersion: "0.9.0-bundle",
            adjacentVersion: "0.9.0-adjacent", installedVersion: "0.9.0-installed"
        ), "0.9.0-bundle")
        XCTAssertEqual(CodexHeadlessVersion.resolve(
            environmentVersion: nil, bundleVersion: nil,
            adjacentVersion: " 0.9.0-adjacent\n", installedVersion: "0.9.0-installed"
        ), "0.9.0-adjacent")
        XCTAssertEqual(CodexHeadlessVersion.resolve(
            environmentVersion: nil, bundleVersion: nil,
            adjacentVersion: nil, installedVersion: "0.9.0-installed"
        ), "0.9.0-installed")
    }
}
