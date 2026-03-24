import Foundation

/// Factory protocol for creating TerminalEngine instances.
/// @MainActor required: SwiftTermEngine.init must run on main thread.
@MainActor
protocol TerminalEngineFactory {
    func makeEngine(for sessionID: SessionID, shell: String, currentDirectory: String?) -> any TerminalEngine
}

/// Live factory — creates terminal engine instances based on the active backend.
@MainActor
struct LiveTerminalEngineFactory: TerminalEngineFactory {
    func makeEngine(for sessionID: SessionID, shell: String, currentDirectory: String? = nil) -> any TerminalEngine {
        switch AppConfig.Backend.activeBackend {
        case .swiftTerm:
            SwiftTermEngine(sessionID: sessionID, shell: shell, currentDirectory: currentDirectory)
        case .libghostty:
            LibghosttyEngine(sessionID: sessionID)
        }
    }
}
