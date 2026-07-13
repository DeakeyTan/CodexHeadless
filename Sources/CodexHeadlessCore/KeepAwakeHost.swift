import Foundation
import IOKit.pwr_mgt

public enum KeepAwakeHostError: LocalizedError {
    case assertionCreationFailed(IOReturn)

    public var errorDescription: String? {
        switch self {
        case .assertionCreationFailed(let result): "IOPM assertion creation failed with IOReturn \(result)."
        }
    }
}

public enum KeepAwakeHost {
    public static func run(instanceID: String) throws -> Never {
        var assertionID = IOPMAssertionID(0)
        let name = "CodexHeadless Keep Awake \(instanceID)" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name,
            &assertionID
        )
        guard result == kIOReturnSuccess else { throw KeepAwakeHostError.assertionCreationFailed(result) }
        print("assertion-created instanceID=\(instanceID) assertionID=\(assertionID)")
        fflush(stdout)
        dispatchMain()
    }
}
