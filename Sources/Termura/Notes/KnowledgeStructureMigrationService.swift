import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "KnowledgeStructureMigrationService")

/// Ensures `<project>/.termura/knowledge/notes/` exists; migrates the legacy
/// `<project>/.termura/notes/` layout into it.
///
/// Older sources/log/attachments migration branches were removed when the
/// knowledge layer was scoped to notes-only. Existing data in those legacy
/// directories is left on disk untouched — the user can `rm -rf` if desired.
///
/// Idempotent: safe to call on every project open.
actor KnowledgeStructureMigrationService {
    private let projectURL: URL
    private let fileManager: any FileManagerProtocol

    init(projectURL: URL, fileManager: any FileManagerProtocol = FileManager.default) {
        self.projectURL = projectURL
        self.fileManager = fileManager
    }

    struct Result: Sendable {
        let migrated: Bool
        let migratedNoteCount: Int
    }

    @discardableResult
    func ensureStructure() async throws -> Result {
        let knowledgeRoot = projectURL
            .appendingPathComponent(AppConfig.Persistence.directoryName)
            .appendingPathComponent(AppConfig.Knowledge.directoryName)

        let notesResult = try migrateLegacyNotesIfNeeded(knowledgeRoot: knowledgeRoot)
        try createNotesDirectory(under: knowledgeRoot)
        return Result(
            migrated: notesResult.migrated,
            migratedNoteCount: notesResult.migratedCount
        )
    }

    // MARK: - Legacy notes migration

    private struct LegacyNotesResult { let migrated: Bool; let migratedCount: Int }

    private func migrateLegacyNotesIfNeeded(knowledgeRoot: URL) throws -> LegacyNotesResult {
        let newNotesDir = knowledgeRoot.appendingPathComponent(AppConfig.Knowledge.notesSubdirectory)
        let oldNotesDir = projectURL
            .appendingPathComponent(AppConfig.Persistence.directoryName)
            .appendingPathComponent(AppConfig.Notes.legacyNotesDirectoryName)

        guard fileManager.fileExists(atPath: oldNotesDir.path),
              !fileManager.fileExists(atPath: newNotesDir.path) else {
            return LegacyNotesResult(migrated: false, migratedCount: 0)
        }

        try fileManager.createDirectory(at: knowledgeRoot, withIntermediateDirectories: true)
        try fileManager.moveItem(at: oldNotesDir, to: newNotesDir)
        let count = countMarkdownFiles(in: newNotesDir)
        logger.info("Migrated legacy notes/ → knowledge/notes/ (\(count) files)")
        return LegacyNotesResult(migrated: true, migratedCount: count)
    }

    private func createNotesDirectory(under knowledgeRoot: URL) throws {
        let notesDir = knowledgeRoot.appendingPathComponent(AppConfig.Knowledge.notesSubdirectory)
        if !fileManager.fileExists(atPath: notesDir.path) {
            try fileManager.createDirectory(at: notesDir, withIntermediateDirectories: true)
        }
    }

    private func countMarkdownFiles(in directory: URL) -> Int {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            // Non-critical: directory may be unreadable; report zero.
            logger.debug("Could not count markdown in \(directory.path): \(error.localizedDescription)")
            return 0
        }
        return entries.count(where: { $0.pathExtension.lowercased() == "md" })
    }
}
