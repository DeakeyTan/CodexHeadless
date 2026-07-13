import Foundation

public struct ProcessTableEntry: Equatable {
    public var pid: Int32
    public var command: String
}

public struct ManagedProcessSnapshot: Equatable {
    public var capturedAt: Date
    public var entries: [ProcessTableEntry]
    public var succeeded: Bool
    public var error: String?
    public var durationMilliseconds: Int

    public static func failed(_ message: String, capturedAt: Date = Date(), durationMilliseconds: Int = 0) -> Self {
        .init(capturedAt: capturedAt, entries: [], succeeded: false, error: message, durationMilliseconds: durationMilliseconds)
    }
}

public protocol ManagedProcessSnapshotProviding: AnyObject {
    func capture() -> ManagedProcessSnapshot
}

public final class ManagedProcessSnapshotProvider: ManagedProcessSnapshotProviding {
    private let logger: CHLogger
    private let now: () -> Date

    public init(logger: CHLogger = CHLogger(), now: @escaping () -> Date = Date.init) {
        self.logger = logger
        self.now = now
    }

    public func capture() -> ManagedProcessSnapshot {
        do {
            let result = try Shell.run("/bin/ps", ["-axo", "pid=,command="], timeoutSeconds: 2)
            guard result.succeeded else {
                let reason = result.timedOut
                    ? "process snapshot timed out"
                    : "process snapshot failed: \(result.terminationDescription) \(result.exitCode)"
                logger.warn("[Perf] process-snapshot durationMs=\(result.durationMilliseconds) result=unknown reason=\(reason)")
                return .failed(reason, capturedAt: now(), durationMilliseconds: result.durationMilliseconds)
            }
            let entries = result.output.split(separator: "\n").compactMap(Self.parse)
            logger.info("[Perf] process-snapshot durationMs=\(result.durationMilliseconds) entries=\(entries.count) result=success")
            return ManagedProcessSnapshot(
                capturedAt: now(), entries: entries, succeeded: true, error: nil,
                durationMilliseconds: result.durationMilliseconds
            )
        } catch {
            return .failed("process snapshot failed: \(error.localizedDescription)", capturedAt: now())
        }
    }

    private static func parse(_ line: Substring) -> ProcessTableEntry? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = text.firstIndex(where: { $0 == " " || $0 == "\t" }),
              let pid = Int32(text[..<separator]) else { return nil }
        return ProcessTableEntry(
            pid: pid,
            command: String(text[separator...]).trimmingCharacters(in: .whitespaces)
        )
    }
}
