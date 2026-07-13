import Foundation

public enum CodexHeadlessVersion {
    public static let developmentFallback = "0.9.0-dev"

    public static var current: String {
        let environmentVersion = ProcessInfo.processInfo.environment["CODEX_HEADLESS_VERSION"]
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let adjacentURL = executable.deletingLastPathComponent().appendingPathComponent("version.txt")
        let adjacentVersion = try? String(contentsOf: adjacentURL, encoding: .utf8)
        var installedVersion: String?
        if executable.path.hasPrefix("/usr/local/bin/") {
            let installedInfo = URL(fileURLWithPath: "/Applications/CodexHeadless.app/Contents/Info.plist")
            installedVersion = (NSDictionary(contentsOf: installedInfo)?["CFBundleShortVersionString"] as? String)
        }
        return resolve(
            environmentVersion: environmentVersion,
            bundleVersion: bundleVersion,
            adjacentVersion: adjacentVersion,
            installedVersion: installedVersion
        )
    }

    public static func resolve(
        environmentVersion: String?,
        bundleVersion: String?,
        adjacentVersion: String?,
        installedVersion: String?
    ) -> String {
        [environmentVersion, bundleVersion, adjacentVersion, installedVersion]
            .compactMap { value -> String? in
                let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let normalized, !normalized.isEmpty else { return nil }
                return normalized.hasPrefix("v") ? String(normalized.dropFirst()) : normalized
            }
            .first ?? developmentFallback
    }
}
