import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectContext+ViewState")

/// Appends `.termura/` to the project's `.gitignore` if not already present.
/// Accepts an injectable `fileManager` for testability; defaults to `FileManager.default`.
func ensureProjectGitignore(
    at projectURL: URL,
    fileManager: any FileManagerProtocol = FileManager.default
) {
    let gitignoreURL = projectURL.appendingPathComponent(".gitignore")
    let entry = ".termura/"

    if fileManager.fileExists(atPath: gitignoreURL.path) {
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
        guard fileManager.fileExists(atPath: gitDir.path) else { return }
        do {
            try (entry + "\n").write(to: gitignoreURL, atomically: true, encoding: .utf8)
            logger.info("Created .gitignore with \(entry)")
        } catch {
            // Non-critical: gitignore creation is a convenience; does not affect app operation.
            logger.warning("Could not create .gitignore: \(error)")
        }
    }
}

// MARK: - Teardown

extension ProjectContext {
    /// Flushes all pending persistence writes (sessions + notes) to guarantee
    /// in-memory state is fully written to DB before shutdown or window close.
    func flushPendingWrites() async {
        await sessionStore.flushPendingWrites()
        await notesViewModel.flushPendingWrites()
    }

    func close() {
        viewStateManager.clearAll()
        engineStore.terminateAll()
        let monitor = dbHealthMonitor
        Task { await monitor.stop() }
        let path = projectURL.path
        logger.info("Closed project at \(path)")
    }
}
