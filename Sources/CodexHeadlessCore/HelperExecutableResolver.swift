import Foundation

public enum HelperExecutableResolver {
    public static func resolveCodexHeadless(
        currentArgument: String? = CommandLine.arguments.first,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> String? {
        resolveExecutable(
            named: "codex-headless",
            currentArgument: currentArgument,
            environmentPath: environmentPath,
            fallbackPaths: [
                "/usr/local/bin/codex-headless",
                "/opt/homebrew/bin/codex-headless"
            ]
        )
    }

    public static func resolveExecutable(
        named executableName: String,
        currentArgument: String?,
        environmentPath: String?,
        fallbackPaths: [String]
    ) -> String? {
        let fileManager = FileManager.default

        if let currentArgument,
           URL(fileURLWithPath: currentArgument).lastPathComponent == executableName,
           currentArgument.contains("/"),
           fileManager.isExecutableFile(atPath: currentArgument) {
            return currentArgument
        }

        let pathCandidates = (environmentPath ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { String($0) + "/" + executableName }

        let siblingCandidates: [String]
        if let currentArgument,
           currentArgument.contains("/") {
            let currentURL = URL(fileURLWithPath: currentArgument)
            siblingCandidates = [
                currentURL.deletingLastPathComponent().appendingPathComponent(executableName).path
            ]
        } else {
            siblingCandidates = []
        }

        return (siblingCandidates + pathCandidates + fallbackPaths).first {
            fileManager.isExecutableFile(atPath: $0)
        }
    }
}
