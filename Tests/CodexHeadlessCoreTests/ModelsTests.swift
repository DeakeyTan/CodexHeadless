import XCTest
@testable import CodexHeadlessCore

final class ModelsTests: XCTestCase {
    func testResolutionParsingAndValidation() throws {
        XCTAssertEqual(try ResolutionManager.parse("2560x1440"), Resolution(width: 2560, height: 1440))
        XCTAssertThrowsError(try ResolutionManager.parse("bad"))
        XCTAssertThrowsError(try ResolutionManager.parse("1000x768"))
        XCTAssertThrowsError(try ResolutionManager.parse("1921x1080"))
    }

    func testPoliciesAndTimingDefaults() throws {
        XCTAssertEqual(try VirtualDisplayPolicy.parse("auto"), .auto)
        XCTAssertEqual(try ConfirmationPolicy.parse("software-virtual-display-only"), .softwareVirtualDisplayOnly)
        XCTAssertEqual(try SoftDisconnectFailureBehavior.parse("restore"), .restore)
        XCTAssertTrue(ConfirmationPolicy.softwareVirtualDisplayOnly.requiresConfirmation(usedManagedVirtualDisplay: true))
        XCTAssertFalse(ConfirmationPolicy.softwareVirtualDisplayOnly.requiresConfirmation(usedManagedVirtualDisplay: false))
        XCTAssertEqual(TimingConfig.default.effectiveRestorePhysicalDisplayGraceSeconds, 5)
        XCTAssertEqual(TimingConfig.default.effectiveRestorePostPromoteStabilizationMilliseconds, 500)
    }

    func testPublicDefaultsAreConservative() {
        let config = AppConfig.default
        XCTAssertEqual(config.schemaVersion, 2)
        XCTAssertEqual(config.virtualDisplay.resolution, Resolution(width: 1920, height: 1080))
        XCTAssertEqual(config.virtualDisplay.scaleMode, VirtualDisplayScaleMode.standard.rawValue)
        XCTAssertEqual(config.softDisconnectBuiltInDisplay, false)
        XCTAssertEqual(config.hideTouchBarInHeadless, false)
        XCTAssertEqual(config.effectiveConfirmation.policy, .softwareVirtualDisplayOnly)
    }

    func testTakeoverRequiresEverySafetyCondition() {
        let safe = DisplayTakeoverVerification(
            displayID: 1,
            exists: true,
            physical: true,
            active: true,
            online: true,
            main: true,
            stable: true
        )
        XCTAssertTrue(safe.safeToDestroyVirtualDisplay)
        var unsafe = safe
        unsafe.main = false
        XCTAssertFalse(unsafe.safeToDestroyVirtualDisplay)
        unsafe = safe
        unsafe.stable = false
        XCTAssertFalse(unsafe.safeToDestroyVirtualDisplay)
    }

    func testFailedHandoffRecoveryResultPreservesReplacementWhenNeeded() {
        XCTAssertEqual(
            FailedHandoffRecoveryResult.physicalDisplayRecovered(displayID: 1),
            .physicalDisplayRecovered(displayID: 1)
        )
        XCTAssertEqual(
            FailedHandoffRecoveryResult.replacementMustRemainActive(reason: "main=false"),
            .replacementMustRemainActive(reason: "main=false")
        )
    }

    func testRuntimePhaseFormatting() {
        var state = RuntimeState.default
        state.phase = .waitingForConfirmation
        state.phaseStartedAt = Date(timeIntervalSince1970: 10)
        state.phaseDeadlineAt = Date(timeIntervalSince1970: 30)
        XCTAssertEqual(RuntimePhaseFormatter.elapsedSeconds(state, now: Date(timeIntervalSince1970: 15)), 5)
        XCTAssertEqual(RuntimePhaseFormatter.deadlineRemainingSeconds(state, now: Date(timeIntervalSince1970: 25)), 5)
    }
}
