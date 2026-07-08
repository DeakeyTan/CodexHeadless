import Foundation

public final class StateStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger: CHLogger

    public init(logger: CHLogger = CHLogger()) {
        self.logger = logger
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> RuntimeState {
        do {
            try CodexHeadlessPaths.ensureDirectories()
            guard FileManager.default.fileExists(atPath: CodexHeadlessPaths.stateFile.path) else {
                try save(.default)
                return .default
            }

            let data = try Data(contentsOf: CodexHeadlessPaths.stateFile)
            return try decoder.decode(RuntimeState.self, from: data)
        } catch {
            logger.error("Failed to load runtime state: \(error.localizedDescription). Using defaults.")
            return .default
        }
    }

    public func save(_ state: RuntimeState) throws {
        try CodexHeadlessPaths.ensureDirectories()
        let data = try encoder.encode(state)
        try data.write(to: CodexHeadlessPaths.stateFile, options: .atomic)
    }

    public func update(_ block: (inout RuntimeState) -> Void) {
        var state = load()
        block(&state)
        do {
            try save(state)
        } catch {
            logger.error("Failed to save runtime state: \(error.localizedDescription)")
        }
    }
}
