import Foundation

#if DEBUG
struct MockTerminalEngineCreation: Sendable {
    let sessionID: SessionID
    let shell: String?
    let currentDirectory: String?
}

/// Mock factory for testing -- returns the injected MockTerminalEngine.
final class MockTerminalEngineFactory: TerminalEngineFactory {
    private let engine: MockTerminalEngine
    private(set) var createdEngines: [MockTerminalEngineCreation] = []

    init(engine: MockTerminalEngine = MockTerminalEngine()) {
        self.engine = engine
    }

    func makeEngine(for sessionID: SessionID, shell: String? = nil, currentDirectory: String? = nil) -> any TerminalEngine {
        createdEngines.append(MockTerminalEngineCreation(
            sessionID: sessionID,
            shell: shell,
            currentDirectory: currentDirectory
        ))
        return engine
    }
}
#endif
