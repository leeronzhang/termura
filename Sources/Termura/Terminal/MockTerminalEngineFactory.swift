import Foundation

#if DEBUG
struct DebugTerminalEngineCreation: Sendable {
    let sessionID: SessionID
    let shell: String?
    let currentDirectory: String?
}

/// Debug preview factory that returns the injected debug terminal engine.
final class DebugTerminalEngineFactory: TerminalEngineFactory {
    private let engine: DebugTerminalEngine
    private(set) var createdEngines: [DebugTerminalEngineCreation] = []

    init(engine: DebugTerminalEngine = DebugTerminalEngine()) {
        self.engine = engine
    }

    func makeEngine(for sessionID: SessionID, shell: String? = nil, currentDirectory: String? = nil) -> any TerminalEngine {
        createdEngines.append(DebugTerminalEngineCreation(
            sessionID: sessionID,
            shell: shell,
            currentDirectory: currentDirectory
        ))
        return engine
    }
}
#endif
