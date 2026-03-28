import Foundation

#if DEBUG

/// Mock factory for testing -- returns the injected MockTerminalEngine.
final class MockTerminalEngineFactory: TerminalEngineFactory {
    private let engine: MockTerminalEngine

    init(engine: MockTerminalEngine = MockTerminalEngine()) {
        self.engine = engine
    }

    func makeEngine(for sessionID: SessionID, shell: String? = nil, currentDirectory: String? = nil) -> any TerminalEngine {
        engine
    }
}

#endif
