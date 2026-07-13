import Foundation

public enum VirtualDisplayHelperEvent: Equatable {
    case authorized(kind: String, capabilityID: String, operationID: String, instanceID: String)
    case ready(instanceID: String, displayID: UInt32)
}

public enum VirtualDisplayHelperProtocol {
    public static let authorizedPrefix = "CH_HELPER_AUTHORIZED"
    public static let readyPrefix = "CH_VIRTUAL_DISPLAY_READY"
    public static let continuePrefix = "CH_PARENT_CONTINUE"

    public static func authorizedLine(
        capabilityID: String,
        operationID: String,
        instanceID: String
    ) -> String {
        "\(authorizedPrefix) kind=virtual-display-host capabilityID=\(capabilityID) operationID=\(operationID) instanceID=\(instanceID)"
    }

    public static func readyLine(instanceID: String, displayID: UInt32) -> String {
        "\(readyPrefix) instanceID=\(instanceID) displayID=\(displayID)"
    }

    public static func continueLine(
        capabilityID: String,
        operationID: String,
        instanceID: String
    ) -> String {
        "\(continuePrefix) capabilityID=\(capabilityID) operationID=\(operationID) instanceID=\(instanceID)"
    }

    public static func parseEvents(_ text: String) -> [VirtualDisplayHelperEvent] {
        guard text.contains("\n") else { return [] }
        var lines = text.components(separatedBy: "\n")
        lines.removeLast() // The final component follows the last complete protocol line.
        return lines.compactMap { parseEvent($0.trimmingCharacters(in: .newlines)) }
    }

    public static func parseEvent(_ line: String) -> VirtualDisplayHelperEvent? {
        let fields = parseFields(line)
        if line.hasPrefix(authorizedPrefix + " "),
           fields["kind"] == "virtual-display-host",
           let capabilityID = fields["capabilityID"],
           let operationID = fields["operationID"],
           let instanceID = fields["instanceID"] {
            return .authorized(
                kind: "virtual-display-host",
                capabilityID: capabilityID,
                operationID: operationID,
                instanceID: instanceID
            )
        }
        if line.hasPrefix(readyPrefix + " "),
           let instanceID = fields["instanceID"],
           let rawDisplayID = fields["displayID"],
           let displayID = UInt32(rawDisplayID) {
            return .ready(instanceID: instanceID, displayID: displayID)
        }
        return nil
    }

    public static func validateContinue(
        _ line: String,
        capabilityID: String,
        operationID: String,
        instanceID: String
    ) -> Bool {
        line == continueLine(
            capabilityID: capabilityID,
            operationID: operationID,
            instanceID: instanceID
        )
    }

    private static func parseFields(_ line: String) -> [String: String] {
        line.split(separator: " ").dropFirst().reduce(into: [:]) { result, component in
            let parts = component.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                result[parts[0]] = parts[1]
            }
        }
    }
}
