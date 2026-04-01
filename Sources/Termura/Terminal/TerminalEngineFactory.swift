import Foundation

/// Factory protocol for creating TerminalEngine instances.
@MainActor
protocol TerminalEngineFactory {
    func makeEngine(for sessionID: SessionID, shell: String?, currentDirectory: String?) -> any TerminalEngine
}

/// Live factory — creates LibghosttyEngine instances (Metal GPU rendering).
@MainActor
struct LiveTerminalEngineFactory: TerminalEngineFactory {
    func makeEngine(for sessionID: SessionID, shell: String? = nil, currentDirectory: String? = nil) -> any TerminalEngine {
        LibghosttyEngine(sessionID: sessionID, workingDirectory: currentDirectory)
    }
}
