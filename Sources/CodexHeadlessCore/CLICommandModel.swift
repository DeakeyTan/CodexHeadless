import Foundation

public struct CLICommand: Equatable {
    public var name: String
    public var arguments: [String]

    public init(name: String, arguments: [String]) {
        self.name = name
        self.arguments = arguments
    }
}

public enum CLIParser {
    public static func parse(_ arguments: [String]) -> CLICommand? {
        guard let name = arguments.first else { return nil }
        return CLICommand(name: name, arguments: Array(arguments.dropFirst()))
    }
}

public enum CLIExitCode {
    public static let success: Int32 = 0
    public static let failure: Int32 = 1
    public static let safetyRefusal: Int32 = 2

    public static func restore(_ result: RestoreResult) -> Int32 {
        result.succeeded ? success : safetyRefusal
    }
}

public enum CLIOutputFormatter {
    public static func restore(_ result: RestoreResult) -> String { result.message }
}
