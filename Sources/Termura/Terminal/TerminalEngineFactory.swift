import Foundation

/// Factory protocol for creating TerminalEngine instances.
@MainActor
protocol TerminalEngineFactory {
    func makeEngine(for sessionID: SessionID, shell: String?, currentDirectory: String?) -> any TerminalEngine
}

/// Live factory — creates LibghosttyEngine instances (Metal GPU rendering).
///
/// Carries an optional `onLifecycleChanged` sink injected at the composition
/// root (`AppDelegate.init`) so each spawned engine can ping the
/// `SessionListBroadcaster` when its child process exits. The sink is only
/// invoked when set; preview / debug paths construct the factory without it
/// and pay nothing.
@MainActor
struct LiveTerminalEngineFactory: TerminalEngineFactory {
    let onEngineLifecycleChanged: (@MainActor @Sendable () -> Void)?

    init(onEngineLifecycleChanged: (@MainActor @Sendable () -> Void)? = nil) {
        self.onEngineLifecycleChanged = onEngineLifecycleChanged
    }

    func makeEngine(for sessionID: SessionID, shell _: String? = nil, currentDirectory: String? = nil) -> any TerminalEngine {
        LibghosttyEngine(
            sessionID: sessionID,
            workingDirectory: currentDirectory,
            onLifecycleChanged: onEngineLifecycleChanged
        )
    }
}
