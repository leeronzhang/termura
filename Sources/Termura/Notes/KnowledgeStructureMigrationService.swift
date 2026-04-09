import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "KnowledgeStructureMigrationService")

/// Ensures the `<project>/.termura/knowledge/` three-tier directory structure exists.
/// Migrates the legacy `<project>/.termura/notes/` directory to `knowledge/notes/` if present.
///
/// Idempotent: safe to call on every project open. The structure check is fast (4 stat calls)
/// and migration runs at most once per project.
actor KnowledgeStructureMigrationService {
    private let projectURL: URL
    private let fileManager: any FileManagerProtocol

    init(projectURL: URL, fileManager: any FileManagerProtocol = FileManager.default) {
        self.projectURL = projectURL
        self.fileManager = fileManager
    }

    /// Result of an `ensureStructure()` call.
    struct Result: Sendable {
        /// True if a legacy migration was performed.
        let migrated: Bool
        /// Number of `.md` files moved during migration (0 if no migration).
        let migratedCount: Int
    }

    /// Ensures the knowledge directory structure exists; migrates legacy notes if needed.
    /// Throws if directory creation or move fails — caller should log and continue.
    @discardableResult
    func ensureStructure() async throws -> Result {
        let knowledgeRoot = projectURL
            .appendingPathComponent(AppConfig.Persistence.directoryName)
            .appendingPathComponent(AppConfig.Knowledge.directoryName)

        let migrationResult = try migrateLegacyIfNeeded(knowledgeRoot: knowledgeRoot)
        try createSubdirectories(under: knowledgeRoot)

        return migrationResult
    }

    // MARK: - Private

    private func migrateLegacyIfNeeded(knowledgeRoot: URL) throws -> Result {
        let newNotesDir = knowledgeRoot.appendingPathComponent(AppConfig.Knowledge.notesSubdirectory)
        let oldNotesDir = projectURL
            .appendingPathComponent(AppConfig.Persistence.directoryName)
            .appendingPathComponent(AppConfig.Notes.legacyNotesDirectoryName)

        // Skip if old doesn't exist or new already exists.
        guard fileManager.fileExists(atPath: oldNotesDir.path),
              !fileManager.fileExists(atPath: newNotesDir.path) else {
            return Result(migrated: false, migratedCount: 0)
        }

        // Ensure parent (knowledge/) exists before moving.
        try fileManager.createDirectory(at: knowledgeRoot, withIntermediateDirectories: true)
        try fileManager.moveItem(at: oldNotesDir, to: newNotesDir)

        let count = countMarkdownFiles(in: newNotesDir)
        logger.info("Migrated legacy notes/ to knowledge/notes/ (\(count) files)")
        return Result(migrated: true, migratedCount: count)
    }

    private func createSubdirectories(under knowledgeRoot: URL) throws {
        let subdirs = [
            AppConfig.Knowledge.notesSubdirectory,
            AppConfig.Knowledge.sourcesSubdirectory,
            AppConfig.Knowledge.logSubdirectory,
            AppConfig.Knowledge.attachmentsSubdirectory
        ]
        for sub in subdirs {
            let url = knowledgeRoot.appendingPathComponent(sub)
            if !fileManager.fileExists(atPath: url.path) {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    private func countMarkdownFiles(in directory: URL) -> Int {
        do {
            let entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return entries.count(where: { $0.pathExtension.lowercased() == "md" })
        } catch {
            logger.warning("Failed to count migrated notes: \(error.localizedDescription)")
            return 0
        }
    }
}
