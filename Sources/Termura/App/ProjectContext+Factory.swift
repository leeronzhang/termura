import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectContext+ViewState")

/// Appends `.termura/` to the project's `.gitignore` if not already present.
func ensureProjectGitignore(at projectURL: URL) {
    let gitignoreURL = projectURL.appendingPathComponent(".gitignore")
    let entry = ".termura/"

    if FileManager.default.fileExists(atPath: gitignoreURL.path) {
        let contents: String
        do {
            contents = try String(contentsOf: gitignoreURL, encoding: .utf8)
        } catch {
            // Non-critical: gitignore management is a convenience feature; project works without it.
            logger.warning("Could not read .gitignore: \(error)")
            return
        }
        let lines = contents.components(separatedBy: .newlines)
        if lines.contains(where: { line in
            line.trimmingCharacters(in: .whitespaces) == entry
        }) { return }
        let suffix = contents.hasSuffix("\n") ? entry + "\n" : "\n" + entry + "\n"
        do {
            try (contents + suffix).write(to: gitignoreURL, atomically: true, encoding: .utf8)
            logger.info("Appended \(entry) to .gitignore")
        } catch {
            // Non-critical: gitignore update is a convenience; does not affect app operation.
            logger.warning("Could not update .gitignore: \(error)")
        }
    } else {
        let gitDir = projectURL.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else { return }
        do {
            try (entry + "\n").write(to: gitignoreURL, atomically: true, encoding: .utf8)
            logger.info("Created .gitignore with \(entry)")
        } catch {
            // Non-critical: gitignore creation is a convenience; does not affect app operation.
            logger.warning("Could not create .gitignore: \(error)")
        }
    }
}

// MARK: - Per-session view state cache & lifecycle

extension ProjectContext {

    /// Returns (or lazily creates) the per-session view state for the given session.
    func viewState(
        for sessionID: SessionID,
        engine: any TerminalEngine
    ) -> SessionViewState {
        if let existing = sessionViewStates[sessionID] { return existing }

        let outputStore = OutputStore(sessionID: sessionID, commandRouter: commandRouter)
        let modeCtrl = InputModeController()
        let timeline = SessionTimeline()
        let vm = TerminalViewModel(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            outputStore: outputStore,
            tokenCountingService: tokenCountingService,
            modeController: modeCtrl,
            agentStateStore: agentStateStore,
            isRestoredSession: sessionStore.isRestoredSession(id: sessionID),
            contextInjectionService: contextInjectionService,
            sessionHandoffService: sessionHandoffService
        )
        let editorVM = EditorViewModel(engine: engine, modeController: modeCtrl)

        let state = SessionViewState(
            outputStore: outputStore,
            viewModel: vm,
            editorViewModel: editorVM,
            modeController: modeCtrl,
            timeline: timeline
        )
        setViewState(state, for: sessionID)
        setOutputStore(outputStore, for: sessionID)
        return state
    }

    /// Remove cached view state when a session is closed.
    func removeViewState(for sessionID: SessionID) {
        setViewState(nil, for: sessionID)
        setOutputStore(nil, for: sessionID)
    }

    // MARK: - OutputStore registry

    func registerOutputStore(_ store: OutputStore, for sessionID: SessionID) {
        setOutputStore(store, for: sessionID)
    }

    func unregisterOutputStore(for sessionID: SessionID) {
        setOutputStore(nil, for: sessionID)
    }

    // MARK: - Teardown

    func close() {
        clearAllCaches()
        engineStore.terminateAll()
        let path = projectURL.path
        logger.info("Closed project at \(path)")
    }
}
