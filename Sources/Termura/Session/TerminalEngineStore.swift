import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalEngineStore")

/// Maps SessionID → TerminalEngine. Owns engine lifecycle.
/// Kept separate from SessionStore to respect single-responsibility.
///
/// `@Observable` is required: `terminalView(for:)` reads `engines` during SwiftUI body
/// evaluation. Without observation tracking, engine creation after the debounce never
/// triggers a re-render, leaving the content area stuck on the empty state.
///
/// ### Startup Invariant
/// **IMPORTANT**: To prevent directory drift and inconsistent startup semantics, do NOT call
/// `createEngine` directly from outside the session management layer. Callers should
/// invoke `SessionStore.ensureEngine(for:shell:)` instead, which handles the resolution
/// of the correct working directory and shell environment.
@Observable
@MainActor
final class TerminalEngineStore {
    private var engines: [SessionID: any TerminalEngine] = [:]
    private let factory: any TerminalEngineFactory

    init(factory: any TerminalEngineFactory) {
        self.factory = factory
    }

    // MARK: - Engine lifecycle

    /// Create and store a new engine for the given session.
    func createEngine(for sessionID: SessionID, shell: String? = nil, currentDirectory: String? = nil) {
        let engine = factory.makeEngine(for: sessionID, shell: shell, currentDirectory: currentDirectory)
        engines[sessionID] = engine
        logger.info("Created engine for session \(sessionID)")
    }

    func engine(for sessionID: SessionID) -> (any TerminalEngine)? {
        engines[sessionID]
    }

    func terminateEngine(for sessionID: SessionID) async {
        guard let engine = engines.removeValue(forKey: sessionID) else { return }
        await engine.terminate()
        logger.info("Terminated engine for session \(sessionID)")
    }

    func terminateAll() async {
        let ids = Array(engines.keys)
        for id in ids {
            await terminateEngine(for: id)
        }
    }

    /// Awaitable bulk termination for project/window shutdown.
    func terminateAllAndWait() async {
        await terminateAll()
    }
}
