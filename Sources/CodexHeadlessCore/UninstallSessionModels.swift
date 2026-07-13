import Foundation

public struct UninstallSessionRequest: Equatable {
    public var installedAppURL: URL
    public var installedCLIURL: URL
    public var launchAgentURL: URL
    public var testRootURL: URL?
    public var barrierDirectoryURL: URL?

    public init(installedAppURL: URL, installedCLIURL: URL, launchAgentURL: URL, testRootURL: URL? = nil, barrierDirectoryURL: URL? = nil) {
        self.installedAppURL = installedAppURL
        self.installedCLIURL = installedCLIURL
        self.launchAgentURL = launchAgentURL
        self.testRootURL = testRootURL
        self.barrierDirectoryURL = barrierDirectoryURL
    }
}

public enum UninstallSessionResult: Equatable {
    case completed
    case refused(String)
    case failed(String)

    public var exitCode: Int32 {
        switch self { case .completed: 0; case .refused: 2; case .failed: 1 }
    }
    public var text: String {
        switch self {
        case .completed: "Uninstall session: COMPLETED"
        case .refused(let reason): "Uninstall session: REFUSED\nReason: \(reason)"
        case .failed(let reason): "Uninstall session: FAILED\nReason: \(reason)"
        }
    }
}

public enum UninstallSessionPathPolicy {
    public static func validate(_ request: UninstallSessionRequest, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let targets = [request.installedAppURL, request.installedCLIURL, request.launchAgentURL]
        guard targets.allSatisfy({ !$0.path.isEmpty && $0.path != "/" && !$0.pathComponents.contains("..") }) else {
            throw CodexHeadlessError.managedResource(message: "Uninstall target path is unsafe.")
        }
        if let root = request.testRootURL {
            guard root.path.hasPrefix("/private/tmp/") || root.path.hasPrefix("/tmp/") else {
                throw CodexHeadlessError.managedResource(message: "Test uninstall root must be under /private/tmp.")
            }
            func normalizedTemporaryPath(_ url: URL) -> String {
                let path = url.standardizedFileURL.path
                return path.hasPrefix("/private/tmp/") ? "/tmp/" + path.dropFirst("/private/tmp/".count) : path
            }
            let lexicalRoot = normalizedTemporaryPath(root)
            let canonicalRoot = normalizedTemporaryPath(root.resolvingSymlinksInPath())
            for target in targets {
                let lexical = normalizedTemporaryPath(target)
                guard lexical.hasPrefix(lexicalRoot + "/") else {
                    throw CodexHeadlessError.managedResource(message: "Test uninstall target escapes its private root: \(target.path)")
                }
                if FileManager.default.fileExists(atPath: target.path) {
                    let canonical = normalizedTemporaryPath(target.resolvingSymlinksInPath())
                    guard canonical.hasPrefix(canonicalRoot + "/") else {
                        throw CodexHeadlessError.managedResource(message: "Test uninstall target symlink escapes its private root: \(target.path)")
                    }
                }
            }
            return
        }
        let expected = [
            "/Applications/CodexHeadless.app",
            "/usr/local/bin/codex-headless",
            home.appendingPathComponent("Library/LaunchAgents/com.codexheadless.app.plist").path
        ]
        guard zip(targets, expected).allSatisfy({ target, allowed in
            target.standardizedFileURL.path == URL(fileURLWithPath: allowed).standardizedFileURL.path
        }) else {
            throw CodexHeadlessError.managedResource(message: "Production uninstall targets do not match the installed CodexHeadless paths.")
        }
    }
}

public protocol UninstallEntryPointManaging: AnyObject {
    func stopAndVerify(launchAgentURL: URL, appExecutableURL: URL) -> String?
}

public protocol UninstallFileDeleting: AnyObject {
    func remove(_ url: URL) throws
}

public protocol UninstallSessionBarrierHandling: AnyObject {
    func afterPreflight() throws
    func deletionCompleted() throws
}
