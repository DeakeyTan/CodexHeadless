import XCTest
@testable import CodexHeadlessCore

final class StatusReportBuilderTests: XCTestCase {
    func testBuilderFormatsProvidedSnapshotWithoutManagers() {
        let snapshot = StatusReportSnapshot(
            config: .default,
            configHealth: .healthy,
            state: .default,
            displays: [makeDisplay(id: 1, builtIn: true, main: true)],
            builtInBrightness: nil
        )
        let report = StatusReportBuilder(snapshot: snapshot).build()
        XCTAssertTrue(report.contains("Mode: Normal"))
        XCTAssertTrue(report.contains("Built-in"))
        XCTAssertTrue(report.contains("Config Health: Healthy"))
    }

    func testHealthyHeadlessSeparatesOperationalSafetyFromNormalReadiness() {
        var state = RuntimeState.default
        state.mode = .headless
        state.keepAwake = true
        var journal = RecoveryJournal(operationID: "test", createdAt: Date())
        journal.stage = .headless
        journal.keepAwakeResource = .init(instanceID: "keep", resourceKind: "keep-awake", operationID: "test", stage: .observed)
        let evidence = OperationalEvidence(
            capturedAt: Date(), source: .explicitStatus, runtimeMode: .headless, operationID: "test", phase: .headlessActive,
            runtimeReadStatus: .success, journal: .activeConsistent(operationID: "test", stage: .headless),
            processSnapshot: .success(durationMilliseconds: 1),
            keepAwake: .init(status: .verifiedOwned, summary: "owned", pid: 42), virtualDisplay: .none,
            display: .init(expectedManagedDisplayID: nil, observedManagedDisplayID: nil, managedDisplayEnumerated: false, expectedDisplayMatchesObserved: nil, physicalMainDisplayID: 1, builtInPresent: false), violations: []
        )
        let report = StatusReportBuilder(snapshot: .init(
            config: .default, configHealth: .healthy, state: state,
            displays: [makeDisplay(id: 1, builtIn: true, main: true)],
            builtInBrightness: nil, operationalEvidence: evidence, journal: journal
        )).build()
        XCTAssertTrue(report.contains("Operational Safety: Managed Headless active"))
        XCTAssertTrue(report.contains("Normal Readiness: Not applicable"))
        XCTAssertFalse(report.contains("Safety Classification: recoveryRequired"))
    }
}
