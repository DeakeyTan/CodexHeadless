import XCTest
@testable import CodexHeadlessCore

final class ConfirmDialogRestoreSuppressionTests: XCTestCase {
    func testTimerCannotReopenDialogAfterRestoreRequestWhileRuntimeStillConfirmRequired() {
        let suppression = ConfirmDialogRestoreSuppression()
        XCTAssertTrue(suppression.shouldPresent(runtimeMode: .confirmRequired))
        suppression.beginRestore()
        XCTAssertFalse(suppression.shouldPresent(runtimeMode: .confirmRequired))
        XCTAssertFalse(suppression.shouldPresent(runtimeMode: .restoring))
    }

    func testTerminalRestoreOrNewEnableClearsSuppression() {
        let suppression = ConfirmDialogRestoreSuppression()
        suppression.beginRestore()
        suppression.clear()
        XCTAssertTrue(suppression.shouldPresent(runtimeMode: .confirmRequired))
    }
}
