import XCTest
@testable import CodexHeadlessCore

final class VirtualDisplayLaunchProtocolTests: XCTestCase {
    func testActualChildEarlyExitIsDetectedWithoutEnumerationTimeout() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 7"]
        let pipe = Pipe()
        let collector = PipeTextCollector()
        pipe.fileHandleForReading.readabilityHandler = { collector.append($0.availableData) }
        process.standardOutput = pipe
        process.standardError = Pipe()
        let manager = VirtualDisplayManager()

        let started = Date()
        try process.run()
        let result = manager.waitForAuthorization(
            process: process, outputCollector: collector, capabilityID: "capability",
            operationID: "operation", instanceID: "instance", timeoutSeconds: 5
        )

        guard case .helperExited(let code, _) = result else {
            return XCTFail("Expected immediate helper exit, got \(result)")
        }
        XCTAssertEqual(code, 7)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        pipe.fileHandleForReading.readabilityHandler = nil
    }

    func testActualChildDelayedAuthorizationIsAcceptedWithoutStageMutation() throws {
        let line = VirtualDisplayHelperProtocol.authorizedLine(
            capabilityID: "capability", operationID: "operation", instanceID: "instance"
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.1; printf '%s\\n' \"$0\"; sleep 1", line]
        let pipe = Pipe()
        let collector = PipeTextCollector()
        pipe.fileHandleForReading.readabilityHandler = { collector.append($0.availableData) }
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()

        let result = VirtualDisplayManager().waitForAuthorization(
            process: process, outputCollector: collector, capabilityID: "capability",
            operationID: "operation", instanceID: "instance", timeoutSeconds: 1
        )

        XCTAssertEqual(result, .authorized)
        process.terminate()
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
    }

    func testAuthorizationTimeoutAndDuplicateOrMismatchedEventsAreDistinct() throws {
        let manager = VirtualDisplayManager(clock: FakeWorkflowClock())
        let running = try runningSleepProcess()
        defer { running.terminate(); running.waitUntilExit() }
        XCTAssertEqual(manager.waitForAuthorization(
            process: running, outputCollector: PipeTextCollector(), capabilityID: "capability",
            operationID: "operation", instanceID: "instance", timeoutSeconds: 0.1
        ), .timedOut)

        let duplicate = PipeTextCollector()
        let line = VirtualDisplayHelperProtocol.authorizedLine(
            capabilityID: "capability", operationID: "operation", instanceID: "instance"
        )
        duplicate.append(Data((line + "\n" + line + "\n").utf8))
        XCTAssertEqual(manager.waitForAuthorization(
            process: running, outputCollector: duplicate, capabilityID: "capability",
            operationID: "operation", instanceID: "instance", timeoutSeconds: 1
        ), .invalidHandshake("duplicate authorization event"))

        let mismatch = PipeTextCollector()
        mismatch.append(Data((VirtualDisplayHelperProtocol.authorizedLine(
            capabilityID: "wrong", operationID: "operation", instanceID: "instance"
        ) + "\n").utf8))
        XCTAssertEqual(manager.waitForAuthorization(
            process: running, outputCollector: mismatch, capabilityID: "capability",
            operationID: "operation", instanceID: "instance", timeoutSeconds: 1
        ), .invalidHandshake("authorization identifiers did not match the launch request"))
    }

    func testDisplayReadyFromImmediatelyExitedHostIsRejected() throws {
        let displays = FakeDisplayManager(displays: [
            makeDisplay(id: 42, builtIn: false, managed: true, main: false)
        ])
        let manager = VirtualDisplayManager(displayManager: displays)
        let collector = PipeTextCollector()
        collector.append(Data((VirtualDisplayHelperProtocol.readyLine(instanceID: "instance", displayID: 42) + "\n").utf8))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 9"]
        try process.run()
        process.waitUntilExit()

        let result = manager.waitForNewDisplayID(
            beforeIDs: [], timeoutSeconds: 5, reportedIDExtraWaitSeconds: 1,
            outputCollector: collector, process: process, expectedInstanceID: "instance"
        )

        guard case .helperExited(let code, _) = result else {
            return XCTFail("Expected exited host rejection, got \(result)")
        }
        XCTAssertEqual(code, 9)
    }

    func testUnrelatedExternalAppearingFirstIsNeverAccepted() throws {
        let displays = FakeDisplayManager(displays: [
            makeDisplay(id: 77, builtIn: false, main: false)
        ])
        let clock = FakeWorkflowClock()
        clock.onSleep = { [weak displays] _ in
            guard displays?.display(id: 42) == nil else { return }
            displays?.currentDisplays.append(makeDisplay(id: 42, builtIn: false, managed: true, main: false))
        }
        let manager = VirtualDisplayManager(displayManager: displays, clock: clock)
        let collector = PipeTextCollector()
        collector.append(Data((VirtualDisplayHelperProtocol.readyLine(instanceID: "instance", displayID: 42) + "\n").utf8))
        let process = try runningSleepProcess()
        defer { process.terminate(); process.waitUntilExit() }

        let result = manager.waitForNewDisplayID(
            beforeIDs: [], timeoutSeconds: 2, reportedIDExtraWaitSeconds: 1,
            outputCollector: collector, process: process, expectedInstanceID: "instance"
        )

        XCTAssertEqual(result, .ready(displayID: 42))
    }

    func testStaleManagedDisplayIsNotAttributedToNewHelper() throws {
        let displays = FakeDisplayManager(displays: [
            makeDisplay(id: 88, builtIn: false, managed: true, main: false)
        ])
        let manager = VirtualDisplayManager(displayManager: displays, clock: FakeWorkflowClock())
        let collector = PipeTextCollector()
        collector.append(Data((VirtualDisplayHelperProtocol.readyLine(instanceID: "instance", displayID: 42) + "\n").utf8))
        let process = try runningSleepProcess()
        defer { process.terminate(); process.waitUntilExit() }

        let result = manager.waitForNewDisplayID(
            beforeIDs: [88], timeoutSeconds: 1, reportedIDExtraWaitSeconds: 1,
            outputCollector: collector, process: process, expectedInstanceID: "instance"
        )

        XCTAssertEqual(result, .displayTimedOut(reportedDisplayID: 42))
    }

    func testDuplicateAndMismatchedReadyEventsAreRejected() throws {
        let process = try runningSleepProcess()
        defer { process.terminate(); process.waitUntilExit() }
        let manager = VirtualDisplayManager(displayManager: FakeDisplayManager(displays: []), clock: FakeWorkflowClock())
        let duplicate = PipeTextCollector()
        let ready = VirtualDisplayHelperProtocol.readyLine(instanceID: "instance", displayID: 42)
        duplicate.append(Data((ready + "\n" + ready + "\n").utf8))
        XCTAssertEqual(manager.waitForNewDisplayID(
            beforeIDs: [], timeoutSeconds: 1, reportedIDExtraWaitSeconds: 1,
            outputCollector: duplicate, process: process, expectedInstanceID: "instance"
        ), .invalidHandshake("duplicate display-ready event"))

        let mismatch = PipeTextCollector()
        mismatch.append(Data((VirtualDisplayHelperProtocol.readyLine(instanceID: "other", displayID: 42) + "\n").utf8))
        XCTAssertEqual(manager.waitForNewDisplayID(
            beforeIDs: [], timeoutSeconds: 1, reportedIDExtraWaitSeconds: 1,
            outputCollector: mismatch, process: process, expectedInstanceID: "instance"
        ), .invalidHandshake("display-ready instance identifier did not match the launch request"))
    }

    func testReportedPhysicalDisplayIDIsRejected() throws {
        let process = try runningSleepProcess()
        defer { process.terminate(); process.waitUntilExit() }
        let displays = FakeDisplayManager(displays: [makeDisplay(id: 42, builtIn: false, managed: false, main: false)])
        let collector = PipeTextCollector()
        collector.append(Data((VirtualDisplayHelperProtocol.readyLine(instanceID: "instance", displayID: 42) + "\n").utf8))
        XCTAssertEqual(VirtualDisplayManager(displayManager: displays, clock: FakeWorkflowClock()).waitForNewDisplayID(
            beforeIDs: [], timeoutSeconds: 1, reportedIDExtraWaitSeconds: 1,
            outputCollector: collector, process: process, expectedInstanceID: "instance"
        ), .invalidHandshake("reported display ID does not identify a CodexHeadless managed virtual display"))
    }

    func testProvisionalHostDoesNotAdvanceGlobalStageBeforeReadyEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecoveryJournalStore(
            journalFile: directory.appendingPathComponent("journal.json"),
            lockFile: directory.appendingPathComponent("journal.lock")
        )
        _ = try store.create(operationID: "operation")
        try store.update { journal in
            journal.stage = .keepAwakeStarted
            journal.virtualDisplayResource = ManagedResourceJournalRecord(
                instanceID: "instance", resourceKind: "virtual-display",
                operationID: "operation", stage: .started
            )
        }
        let ownership = ManagedProcessOwnershipRecord(
            instanceID: "instance", pid: 123, executableCanonicalPath: "/tmp/helper",
            executableFileIdentity: "1:2", processStartTime: "3",
            expectedCommandFragments: ["virtual-display-host"], ownerOperationID: "operation",
            resourceKind: "virtual-display", createdAt: Date()
        )
        let host = VirtualDisplayHostRecord(
            instanceID: "instance", pid: 123, executablePath: "/tmp/helper",
            startedAt: Date(), ownership: ownership
        )
        let coordinator = VirtualDisplayLaunchJournalCoordinator(journalStore: store)

        try coordinator.persistProvisionalHost(host, ownership: ownership)
        XCTAssertEqual(try store.read()?.stage, .keepAwakeStarted)
        XCTAssertNil(try store.read()?.virtualDisplayResource?.displayID)

        try coordinator.persistReadyDisplay(42, host: host)
        XCTAssertEqual(try store.read()?.stage, .virtualDisplayStarted)
        XCTAssertEqual(try store.read()?.virtualDisplayResource?.displayID, 42)
    }

    func testAuthorizationAndReadyEventsRoundTrip() {
        let authorization = VirtualDisplayHelperProtocol.authorizedLine(
            capabilityID: "capability", operationID: "operation", instanceID: "instance"
        )
        let ready = VirtualDisplayHelperProtocol.readyLine(instanceID: "instance", displayID: 42)

        XCTAssertEqual(VirtualDisplayHelperProtocol.parseEvents(authorization + "\n"), [
            .authorized(kind: "virtual-display-host", capabilityID: "capability", operationID: "operation", instanceID: "instance")
        ])
        XCTAssertEqual(VirtualDisplayHelperProtocol.parseEvents(authorization + "\n" + ready + "\n"), [
            .authorized(kind: "virtual-display-host", capabilityID: "capability", operationID: "operation", instanceID: "instance"),
            .ready(instanceID: "instance", displayID: 42)
        ])
    }

    func testPartialProtocolLineIsNotAccepted() {
        let line = VirtualDisplayHelperProtocol.authorizedLine(
            capabilityID: "capability", operationID: "operation", instanceID: "instance"
        )
        XCTAssertTrue(VirtualDisplayHelperProtocol.parseEvents(line).isEmpty)
        XCTAssertTrue(VirtualDisplayHelperProtocol.parseEvents(String(line.dropLast(3))).isEmpty)
    }

    func testWrongOrMissingIdentifiersAreRejected() {
        XCTAssertTrue(VirtualDisplayHelperProtocol.parseEvents(
            "CH_HELPER_AUTHORIZED kind=virtual-display-host capabilityID=cap operationID=op\n"
        ).isEmpty)
        XCTAssertTrue(VirtualDisplayHelperProtocol.parseEvents(
            "CH_VIRTUAL_DISPLAY_READY instanceID=i displayID=not-a-number\n"
        ).isEmpty)
    }

    func testParentContinuationRequiresExactIdentifiers() {
        let line = VirtualDisplayHelperProtocol.continueLine(
            capabilityID: "capability", operationID: "operation", instanceID: "instance"
        )
        XCTAssertTrue(VirtualDisplayHelperProtocol.validateContinue(
            line, capabilityID: "capability", operationID: "operation", instanceID: "instance"
        ))
        XCTAssertFalse(VirtualDisplayHelperProtocol.validateContinue(
            line, capabilityID: "other", operationID: "operation", instanceID: "instance"
        ))
    }

    func testDuplicateEventsRemainVisibleToParentValidation() {
        let line = VirtualDisplayHelperProtocol.authorizedLine(
            capabilityID: "capability", operationID: "operation", instanceID: "instance"
        )
        XCTAssertEqual(VirtualDisplayHelperProtocol.parseEvents(line + "\n" + line + "\n").count, 2)
    }

    private func runningSleepProcess() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        try process.run()
        return process
    }
}
