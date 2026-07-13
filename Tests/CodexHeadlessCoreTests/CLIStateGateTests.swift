import XCTest
@testable import CodexHeadlessCore

final class CLIStateGateTests: XCTestCase {
    func testNormalOnlyMatrix() {
        for mode in allModes {
            var state = RuntimeState.default
            state.mode = mode
            if mode == .normal {
                XCTAssertNoThrow(try CLIStateGate.validate(state: state, requirement: .normalOnly, operation: "mutate"))
            } else {
                XCTAssertThrowsError(try CLIStateGate.validate(state: state, requirement: .normalOnly, operation: "mutate"))
            }
        }
    }

    func testRestoreResultExitCodes() {
        XCTAssertEqual(CLIExitCode.restore(.completed), CLIExitCode.success)
        XCTAssertEqual(CLIExitCode.restore(.pausedForSafety(reason: "wait")), CLIExitCode.safetyRefusal)
        XCTAssertEqual(CLIExitCode.restore(.cleanupIncomplete(progress: .init(), reason: "pending")), CLIExitCode.safetyRefusal)
    }

    func testParser() {
        XCTAssertEqual(CLIParser.parse(["config", "get"])?.name, "config")
        XCTAssertEqual(CLIParser.parse(["config", "get"])?.arguments, ["get"])
        XCTAssertNil(CLIParser.parse([]))
    }

    private var allModes: [HeadlessMode] {
        [.normal, .preparing, .confirmRequired, .headless, .fallback, .restoring, .error, .recoveryRequired]
    }
}
