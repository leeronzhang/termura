import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NoteMigrationService")

/// One-time migration: exports existing GRDB notes to Markdown files.
/// Idempotent — uses a sentinel file (`.migrated`) to skip if already done.
actor NoteMigrationService {
    private let db: any DatabaseServiceProtocol
    private let fileService: any NoteFileServiceProtocol
    private let notesDirectory: URL
    private let fileManager: any FileManagerProtocol

    private var sentinelPath: String {
        notesDirectory.appendingPathComponent(".migrated").path
    }

    init(db: any DatabaseServiceProtocol,
         fileService: any NoteFileServiceProtocol,
         notesDirectory: URL,
         fileManager: any FileManagerProtocol = FileManager.default) {
        self.db = db
        self.fileService = fileService
        self.notesDirectory = notesDirectory
        self.fileManager = fileManager
    }

    /// Returns `true` if migration was performed, `false` if already done.
    /// Only writes the `.migrated` sentinel when ALL notes are successfully exported.
    /// If any note fails, the error is thrown so that the next launch retries the full migration.
    func migrateIfNeeded() async throws -> Bool {
        if fileManager.fileExists(atPath: sentinelPath) {
            return false
        }

        if !fileManager.fileExists(atPath: notesDirectory.path) {
            try fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        }

        let records = try await fetchLegacyNotes()
        guard !records.isEmpty else {
            try writeSentinel()
            logger.info("No legacy notes to migrate")
            return false
        }

        var failedIDs: [NoteID] = []
        var migrated = 0
        for record in records {
            do {
                _ = try await fileService.writeNote(record, to: notesDirectory)
                migrated += 1
            } catch {
                logger.error("Failed to migrate note \(record.id): \(error.localizedDescription)")
                failedIDs.append(record.id)
            }
        }

        guard failedIDs.isEmpty else {
            let failed = failedIDs.count
            let total = records.count
            logger.error("Migration incomplete: \(failed)/\(total) notes failed. Will retry next launch.")
            throw MigrationError.partialFailure(
                migrated: migrated,
                failedIDs: failedIDs
            )
        }

        try writeSentinel()
        logger.info("Migrated \(migrated)/\(records.count) notes from GRDB to Markdown files")
        return true
    }

    enum MigrationError: Error, LocalizedError {
        case partialFailure(migrated: Int, failedIDs: [NoteID])

        var errorDescription: String? {
            switch self {
            case let .partialFailure(migrated, failedIDs):
                "Note migration incomplete: \(migrated) succeeded, \(failedIDs.count) failed. Will retry on next launch."
            }
        }
    }

    // MARK: - Private

    private func fetchLegacyNotes() async throws -> [NoteRecord] {
        try await db.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT id, title, body, is_snippet, created_at, updated_at
                FROM notes WHERE archived_at IS NULL
                ORDER BY updated_at DESC
                """
            )
            return rows.compactMap { row -> NoteRecord? in
                let idStr: String = row["id"]
                guard let uuid = UUID(uuidString: idStr) else { return nil }
                let title: String = row["title"]
                let body: String = row["body"]
                let isFavorite: Int = row["is_snippet"]
                let createdAt: Double = row["created_at"]
                let updatedAt: Double = row["updated_at"]
                var record = NoteRecord(
                    id: NoteID(rawValue: uuid), title: title, body: body,
                    isFavorite: isFavorite != 0
                )
                record.createdAt = Date(timeIntervalSince1970: createdAt)
                record.updatedAt = Date(timeIntervalSince1970: updatedAt)
                return record
            }
        }
    }

    private func writeSentinel() throws {
        let data = Data("migrated".utf8)
        do {
            try data.write(to: URL(fileURLWithPath: sentinelPath), options: .atomic)
        } catch {
            logger.error("Failed to write migration sentinel: \(error.localizedDescription)")
            throw error
        }
    }
}
