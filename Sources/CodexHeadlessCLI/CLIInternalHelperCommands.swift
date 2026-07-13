import CodexHeadlessCore
import Foundation

enum CLIInternalHelperCommands {
    static func run(_ args: [String]) throws -> Never {
        guard args.count >= 4,
              let kind = InternalHelperKind(rawValue: args[0]) else {
            fail("Internal helper authorization is required.", code: 64)
        }
        let capabilityID = args[1]
        let nonce = args[2]
        let operationID = args[3]
        _ = try HelperCapabilityStore().consume(
            capabilityID: capabilityID,
            nonce: nonce,
            operationID: operationID,
            kind: kind
        )
        let payload = Array(args.dropFirst(4))

        switch kind {
        case .keepAwakeHost:
            guard payload.count == 1 else { fail("Invalid Keep Awake helper payload.", code: 64) }
            try KeepAwakeHost.run(instanceID: payload[0])
        case .virtualDisplayHost:
            guard payload.count == 5,
                  let width = Int(payload[1]),
                  let height = Int(payload[2]),
                  let refreshRate = Int(payload[3]) else {
                fail("Invalid virtual display helper payload.", code: 64)
            }
            let resolution = Resolution(width: width, height: height)
            try ResolutionManager.validate(resolution)
            let instanceID = payload[0]
            writeProtocolLine(VirtualDisplayHelperProtocol.authorizedLine(
                capabilityID: capabilityID,
                operationID: operationID,
                instanceID: instanceID
            ))
            guard let parentLine = readParentContinue(),
                  VirtualDisplayHelperProtocol.validateContinue(
                    parentLine,
                    capabilityID: capabilityID,
                    operationID: operationID,
                    instanceID: instanceID
                  ) else {
                fail("Virtual display helper parent continuation was not authorized.", code: 65)
            }
            try VirtualDisplayHost.run(
                resolution: resolution,
                refreshRate: refreshRate,
                scaleMode: payload[4],
                instanceID: instanceID
            )
        case .touchBarApply:
            guard payload.count == 2,
                  let action = TouchBarExperimentAction(rawValue: payload[0]),
                  let variant = TouchBarExperimentVariant(rawValue: payload[1]),
                  let method = TouchBarPrivateBridge.shared.setHidden(action: action, variant: variant) else {
                fail("Private Touch Bar helper failed.", code: 2)
            }
            print(method)
            exit(0)
        case .softDisconnectApply:
            guard payload.count == 3,
                  let displayID = UInt32(payload[0]),
                  payload[1] == "disable" || payload[1] == "enable" else {
                fail("Invalid soft-disconnect helper payload.", code: 64)
            }
            let disabled = payload[1] == "disable"
            let method: String?
            if payload[2] == "default" {
                method = CoreDisplayPrivateBridge.shared.setUserDisabledMethod(displayID: displayID, disabled: disabled)
            } else if let variant = SoftDisconnectExperimentVariant(rawValue: payload[2]) {
                method = CoreDisplayPrivateBridge.shared.setUserDisabledMethod(displayID: displayID, disabled: disabled, variant: variant)
            } else {
                method = nil
            }
            guard let method else { fail("Private soft-disconnect helper failed.", code: 2) }
            print(method)
            exit(0)
        }
    }

    private static func writeProtocolLine(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
        try? FileHandle.standardOutput.synchronize()
    }

    private static func readParentContinue() -> String? {
        let data = FileHandle.standardInput.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \Character.isNewline).first.map(String.init)
    }
}
