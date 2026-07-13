import Foundation

enum HelperProcessCandidateVerification: Equatable {
    case none
    case verified(pid: Int32)
    case unknown(pid: Int32, reason: String)
}

enum HelperProcessCandidateDetector {
    static func candidatePID(
        in snapshot: ManagedProcessSnapshot,
        kind: InternalHelperKind,
        excludingPID: Int32 = getpid()
    ) -> Int32? {
        snapshot.entries.first { entry in
            entry.pid != excludingPID && hasExactCommandStructure(entry.command, kind: kind)
        }?.pid
    }

    static func verify(
        snapshot: ManagedProcessSnapshot,
        kind: InternalHelperKind,
        inspector: ManagedProcessInspecting,
        excludingPID: Int32 = getpid()
    ) -> HelperProcessCandidateVerification {
        guard let pid = candidatePID(in: snapshot, kind: kind, excludingPID: excludingPID) else { return .none }
        guard inspector.isRunning(pid: pid), let facts = inspector.facts(pid: pid) else {
            return .unknown(pid: pid, reason: "helper-shaped process identity could not be collected")
        }
        let executableName = URL(fileURLWithPath: facts.executableCanonicalPath).lastPathComponent.lowercased()
        guard executableName == "codex-headless",
              facts.executableFileIdentity != nil,
              facts.processStartTime != nil,
              hasExactCommandStructure(facts.command, kind: kind) else {
            return .unknown(pid: pid, reason: "helper-shaped process is not independently verified as CodexHeadless")
        }
        return .verified(pid: pid)
    }

    static func hasExactCommandStructure(_ command: String, kind: InternalHelperKind) -> Bool {
        let tokens = shellTokens(command)
        guard tokens.count >= 3 else { return false }
        return URL(fileURLWithPath: tokens[0]).lastPathComponent.lowercased() == "codex-headless"
            && tokens[1] == "internal-helper"
            && tokens[2] == kind.rawValue
    }

    private static func shellTokens(_ command: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in command {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
                continue
            }
            if character == "\"" || character == "'" { quote = character; continue }
            if character.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
