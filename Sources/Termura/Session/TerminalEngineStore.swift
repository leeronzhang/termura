import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalEngineStore")

/// Maps SessionID → TerminalEngine. Owns engine lifecycle.
/// Kept separate from SessionStore to respect single-responsibility.
@MainActor
final class TerminalEngineStore: ObservableObject {
    private var engines: [SessionID: any TerminalEngine] = [:]
    private let factory: any TerminalEngineFactory

    init(factory: any TerminalEngineFactory) {
        self.factory = factory
    }

    // MARK: - Engine lifecycle

    /// Create and store a new engine for the given session.
    @discardableResult
    func createEngine(for sessionID: SessionID, shell: String) -> any TerminalEngine {
        let engine = factory.makeEngine(for: sessionID, shell: shell)
        engines[sessionID] = engine
        logger.info("Created engine for session \(sessionID)")
        return engine
    }

    func engine(for sessionID: SessionID) -> (any TerminalEngine)? {
        engines[sessionID]
    }

    func terminateEngine(for sessionID: SessionID) {
        guard let engine = engines.removeValue(forKey: sessionID) else { return }
        Task {
            await engine.terminate()
        }
        logger.info("Terminated engine for session \(sessionID)")
    }

    func terminateAll() {
        let ids = Array(engines.keys)
        for id in ids {
            terminateEngine(for: id)
        }
    }
}
