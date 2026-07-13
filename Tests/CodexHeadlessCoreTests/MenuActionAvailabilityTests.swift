import XCTest
@testable import CodexHeadlessCore

final class MenuActionAvailabilityTests: XCTestCase {
    func testHeadlessDisablesPowerToggleAndQuit() {
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        let availability = MenuActionAvailability.make(state: state, configHealthy: true, operationBusy: false)
        XCTAssertFalse(availability.canEnable)
        XCTAssertFalse(availability.canToggleKeepAwake)
        XCTAssertFalse(availability.canQuit)
        XCTAssertTrue(availability.canRestore)
    }

    func testNormalHealthyStateEnablesExpectedActions() {
        let availability = MenuActionAvailability.make(state: .default, configHealthy: true, operationBusy: false)
        XCTAssertTrue(availability.canEnable)
        XCTAssertTrue(availability.canToggleKeepAwake)
        XCTAssertTrue(availability.canQuit)
        XCTAssertFalse(availability.canConfirm)
    }
}

final class MenuDynamicPresentationTests: XCTestCase {
    func testConfirmationAndCountdownUpdateWithoutChangingStructure() {
        var state = RuntimeState.default
        state.mode = .confirmRequired
        state.replacementDisplayType = "managedVirtual"
        state.rollbackDeadline = Date(timeIntervalSince1970: 130)
        let presentation = MenuDynamicPresentation.make(
            state: state,
            operationBusy: true,
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertTrue(presentation.showsConfirmationActions)
        XCTAssertFalse(presentation.showsSettings)
        XCTAssertTrue(presentation.showsOperationBusy)
        XCTAssertTrue(presentation.showsReplacement)
        XCTAssertEqual(presentation.rollbackRemainingSeconds, 30)
    }
}
