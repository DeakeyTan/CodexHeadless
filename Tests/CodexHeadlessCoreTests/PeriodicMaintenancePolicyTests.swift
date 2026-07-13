import XCTest
@testable import CodexHeadlessCore

final class PeriodicMaintenancePolicyTests: XCTestCase {
    let policy = PeriodicMaintenancePolicy()

    func testNormalUsesThirtySecondAssessmentInterval() {
        var state = RuntimeState.default
        state.mode = .normal
        XCTAssertEqual(policy.actions(state: state, uptime: 10, lastNormalAssessmentUptime: 0, lastHeadlessReconcileUptime: nil), [.refreshCooldown])
        XCTAssertEqual(policy.actions(state: state, uptime: 31, lastNormalAssessmentUptime: 0, lastHeadlessReconcileUptime: nil), [.refreshCooldown, .refreshCleanNormalCache])
    }

    func testHeadlessUsesTenSecondReconcileInterval() {
        var state = RuntimeState.default
        state.mode = .headless
        XCTAssertEqual(policy.actions(state: state, uptime: 5, lastNormalAssessmentUptime: nil, lastHeadlessReconcileUptime: 0), [])
        XCTAssertEqual(policy.actions(state: state, uptime: 10, lastNormalAssessmentUptime: nil, lastHeadlessReconcileUptime: 0), [.reconcileManagedResources])
    }

    func testModeMatrixAvoidsDuplicateWorkflowMaintenance() {
        var state = RuntimeState.default
        state.mode = .preparing
        XCTAssertTrue(policy.actions(state: state, uptime: 1, lastNormalAssessmentUptime: nil, lastHeadlessReconcileUptime: nil).isEmpty)
        state.mode = .confirmRequired
        XCTAssertEqual(policy.actions(state: state, uptime: 1, lastNormalAssessmentUptime: nil, lastHeadlessReconcileUptime: nil), [.checkRollback, .reconcileManagedResources])
        state.mode = .restoring; state.phase = .restorePaused
        XCTAssertEqual(policy.actions(state: state, uptime: 1, lastNormalAssessmentUptime: nil, lastHeadlessReconcileUptime: nil), [.resumePausedRestore])
        state.mode = .error
        XCTAssertTrue(policy.actions(state: state, uptime: 1, lastNormalAssessmentUptime: nil, lastHeadlessReconcileUptime: nil).isEmpty)
    }
}
