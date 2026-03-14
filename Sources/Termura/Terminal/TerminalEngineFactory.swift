import Foundation

/// Factory protocol for creating TerminalEngine instances.
/// @MainActor required: SwiftTermEngine.init must run on main thread.
@MainActor
protocol TerminalEngineFactory {
    func makeEngine(for sessionID: SessionID, shell: String) -> any TerminalEngine
}

/// Live factory — creates real SwiftTermEngine instances.
@MainActor
struct LiveTerminalEngineFactory: TerminalEngineFactory {
    func makeEngine(for sessionID: SessionID, shell: String) -> any TerminalEngine {
        SwiftTermEngine(sessionID: sessionID, shell: shell)
    }
}
