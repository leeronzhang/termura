import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "FileBackedNoteRepository")

// MARK: - File-backed Note Repository

/// Notes stored as Markdown files in `<project>/.termura/notes/`.
/// GRDB is used only as a rebuild-able FTS5 search cache.
actor FileBackedNoteRepository: NoteRepositoryProtocol {
    let notesDirectory: URL
    let fileService: any NoteFileServiceProtocol
    let db: any DatabaseServiceProtocol
    private let clock: any AppClock
    let fileManager: any FileManagerProtocol

    /// In-memory index: NoteID -> (record, file URL).
    var index: [NoteID: IndexEntry] = [:]
    var isLoaded = false
    /// Set during writes to suppress file-watcher events from our own changes.
    private(set) var isWriting = false
    /// File-system watcher task — cancelled on stopWatching().
    var watchTask: Task<Void, Never>?
    var watcher: (any NoteDirectoryWatcherProtocol)?

    struct IndexEntry {
        var record: NoteRecord
        var url: URL
        /// File modification date at last read — used by incrementalSync to skip unchanged files.
        var modificationDate: Date?
    }

    init(notesDirectory: URL,
         fileService: any NoteFileServiceProtocol,
         db: any DatabaseServiceProtocol,
         clock: any AppClock = LiveClock(),
         fileManager: any FileManagerProtocol = FileManager.default) {
        self.notesDirectory = notesDirectory
        self.fileService = fileService
        self.db = db
        self.clock = clock
        self.fileManager = fileManager
    }

    // MARK: - NoteRepositoryProtocol

    func fetchAll() async throws -> [NoteRecord] {
        try await ensureLoaded()
        return index.values
            .map(\.record)
            .sorted(by: NoteRecord.displayOrder)
    }

    func save(_ note: NoteRecord) async throws {
        try await ensureLoaded()

        var updated = note
        updated.updatedAt = clock.now()

        isWriting = true
        defer { isWriting = false }

        // If title changed, remove old file first (abort on failure to prevent duplicates).
        if let existing = index[note.id],
           await fileService.filename(for: existing.record) != fileService.filename(for: updated) {
            try await fileService.deleteNote(at: existing.url)
        }

        let url = try await fileService.writeNote(updated, to: notesDirectory)
        index[note.id] = IndexEntry(record: updated, url: url, modificationDate: fileModDate(at: url))

        try await upsertCache(updated)
    }

    func delete(id: NoteID) async throws {
        try await ensureLoaded()
        isWriting = true
        defer { isWriting = false }
        if let entry = index[id] { try await fileService.deleteNote(at: entry.url) }
        index[id] = nil
        try await deleteCache(id: id)
    }

    func search(query: String) async throws -> [NoteRecord] {
        guard query.count >= AppConfig.Search.minQueryLength else { return [] }
        try await ensureLoaded()
        let ftsQuery = FTS5.escapeQuery(query)
        return try await db.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT n.* FROM notes n
                JOIN notes_fts fts ON n.rowid = fts.rowid
                WHERE notes_fts MATCH ? AND n.archived_at IS NULL
                ORDER BY rank LIMIT ?
                """,
                arguments: [ftsQuery, AppConfig.Search.maxResults]
            )
            return try rows.map { row in
                let idStr: String = row["id"]
                guard let uuid = UUID(uuidString: idStr) else {
                    throw RepositoryError.invalidID(rawValue: idStr, entity: "Note")
                }
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

    // MARK: - Private

    private func ensureLoaded() async throws {
        guard !isLoaded else { return }
        if !fileManager.fileExists(atPath: notesDirectory.path) {
            try fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        }
        try await reloadFromDisk()
        try await rebuildCache()
    }

    func fileModDate(at url: URL) -> Date? {
        do {
            return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        } catch {
            // Non-critical: modification date is used only for incremental sync optimization.
            logger.debug("Could not read modDate for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    func upsertCache(_ note: NoteRecord) async throws {
        let id = note.id.rawValue.uuidString
        let fav = note.isFavorite ? 1 : 0
        let created = note.createdAt.timeIntervalSince1970
        let updated = note.updatedAt.timeIntervalSince1970
        try await db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO notes (id,title,body,is_snippet,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                arguments: [id, note.title, note.body, fav, created, updated]
            )
        }
    }

    func deleteCache(id: NoteID) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM notes WHERE id = ?", arguments: [id.rawValue.uuidString])
        }
    }
}
