import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "KnowledgeStructureMigrationService")

/// Ensures the `<project>/.termura/knowledge/` directory layout matches the
/// current spec (`docs/knowledge-visualization-roadmap.md`).
///
/// Idempotent: safe to call on every project open. Each branch checks whether
/// the source path exists before doing work, so projects already on the new
/// layout pay only stat-call cost.
///
/// Migrations performed (in order):
///   1. Legacy `<project>/.termura/notes/` → `knowledge/notes/`
///   2. `knowledge/sources/papers/*` → `knowledge/sources/articles/`, drop papers/
///   3. `knowledge/sources/code/*`   → `knowledge/sources/articles/`, drop code/
///   4. `knowledge/attachments/*`    → `knowledge/notes/attachments/`, drop attachments/
///   5. Create the canonical subdirectory set under `knowledge/`
actor KnowledgeStructureMigrationService {
    private let projectURL: URL
    private let fileManager: any FileManagerProtocol

    init(projectURL: URL, fileManager: any FileManagerProtocol = FileManager.default) {
        self.projectURL = projectURL
        self.fileManager = fileManager
    }

    /// Result of an `ensureStructure()` call.
    struct Result: Sendable {
        /// True if any of the four migration branches actually moved something.
        let migrated: Bool
        /// Number of `.md` files moved by the legacy notes migration (branch 1 only).
        let migratedNoteCount: Int
    }

    @discardableResult
    func ensureStructure() async throws -> Result {
        let knowledgeRoot = projectURL
            .appendingPathComponent(AppConfig.Persistence.directoryName)
            .appendingPathComponent(AppConfig.Knowledge.directoryName)

        var migrated = false
        var migratedNoteCount = 0

        let notesResult = try migrateLegacyNotesIfNeeded(knowledgeRoot: knowledgeRoot)
        migrated = migrated || notesResult.migrated
        migratedNoteCount = notesResult.migratedCount

        if try mergeLegacySourcesBucketsIntoArticles(knowledgeRoot: knowledgeRoot) {
            migrated = true
        }
        if try migrateLegacyAttachmentsIntoNotes(knowledgeRoot: knowledgeRoot) {
            migrated = true
        }

        try createSubdirectories(under: knowledgeRoot)

        return Result(migrated: migrated, migratedNoteCount: migratedNoteCount)
    }

    // MARK: - Branch 1: legacy notes → knowledge/notes

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

    // MARK: - Branch 2 + 3: legacy sources buckets → articles

    /// Returns true if anything was moved or any legacy bucket dir was removed.
    private func mergeLegacySourcesBucketsIntoArticles(knowledgeRoot: URL) throws -> Bool {
        let sourcesDir = knowledgeRoot.appendingPathComponent(AppConfig.Knowledge.sourcesSubdirectory)
        let articlesDir = sourcesDir.appendingPathComponent("articles")
        var didWork = false
        for bucket in AppConfig.Knowledge.legacySourcesBuckets {
            let legacyDir = sourcesDir.appendingPathComponent(bucket)
            guard fileManager.fileExists(atPath: legacyDir.path) else { continue }

            try fileManager.createDirectory(at: articlesDir, withIntermediateDirectories: true)
            let entries = listEntries(at: legacyDir)
            for entry in entries {
                let dest = articlesDir.appendingPathComponent(entry.lastPathComponent)
                if fileManager.fileExists(atPath: dest.path) {
                    logger.warning("Skipping migration of \(entry.lastPathComponent): already exists in articles/")
                    continue
                }
                try fileManager.moveItem(at: entry, to: dest)
                didWork = true
            }
            try removeIfEmpty(at: legacyDir)
            logger.info("Migrated knowledge/sources/\(bucket) → articles/")
        }
        return didWork
    }

    // MARK: - Branch 4: knowledge/attachments → knowledge/notes/attachments

    /// Returns true if anything was moved or the legacy attachments dir was removed.
    private func migrateLegacyAttachmentsIntoNotes(knowledgeRoot: URL) throws -> Bool {
        let legacyAttachments = knowledgeRoot
            .appendingPathComponent(AppConfig.Knowledge.legacyAttachmentsSubdirectoryName)
        guard fileManager.fileExists(atPath: legacyAttachments.path) else { return false }

        let newAttachments = knowledgeRoot
            .appendingPathComponent(AppConfig.Knowledge.notesSubdirectory)
            .appendingPathComponent(AppConfig.Knowledge.attachmentsSubdirectoryWithinNotes)
        try fileManager.createDirectory(at: newAttachments, withIntermediateDirectories: true)

        let entries = listEntries(at: legacyAttachments)
        var movedAny = false
        for entry in entries {
            let dest = newAttachments.appendingPathComponent(entry.lastPathComponent)
            if fileManager.fileExists(atPath: dest.path) {
                logger.warning("Skipping migration of attachment \(entry.lastPathComponent): already exists in notes/attachments/")
                continue
            }
            try fileManager.moveItem(at: entry, to: dest)
            movedAny = true
        }
        try removeIfEmpty(at: legacyAttachments)
        logger.info("Migrated knowledge/attachments → knowledge/notes/attachments")
        return movedAny || true
    }

    // MARK: - Canonical subdirectory creation

    private func createSubdirectories(under knowledgeRoot: URL) throws {
        let notesDir = knowledgeRoot.appendingPathComponent(AppConfig.Knowledge.notesSubdirectory)
        let sourcesDir = knowledgeRoot.appendingPathComponent(AppConfig.Knowledge.sourcesSubdirectory)
        let logDir = knowledgeRoot.appendingPathComponent(AppConfig.Knowledge.logSubdirectory)
        let attachmentsDir = notesDir.appendingPathComponent(
            AppConfig.Knowledge.attachmentsSubdirectoryWithinNotes
        )

        var dirs = [notesDir, attachmentsDir, sourcesDir, logDir]
        for bucket in AppConfig.Knowledge.sourcesBuckets {
            dirs.append(sourcesDir.appendingPathComponent(bucket))
        }
        for url in dirs where !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Helpers

    private func removeIfEmpty(at url: URL) throws {
        guard listEntries(at: url).isEmpty else { return }
        try fileManager.removeItem(at: url)
    }

    private func countMarkdownFiles(in directory: URL) -> Int {
        listEntries(at: directory).count(where: { $0.pathExtension.lowercased() == "md" })
    }

    /// Reads directory contents tolerantly: any I/O failure returns an empty array
    /// (the surrounding migration logic treats empty / unreadable as "nothing to do").
    private func listEntries(at url: URL) -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            // Non-critical: directory may not exist yet or be unreadable; log and skip.
            logger.debug("Could not enumerate \(url.path): \(error.localizedDescription)")
            return []
        }
    }
}
