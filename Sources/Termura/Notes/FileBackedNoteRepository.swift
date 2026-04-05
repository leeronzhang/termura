import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "FileBackedNoteRepository")

// MARK: - File-backed Note Repository

/// Notes stored as Markdown files in `<project>/.termura/notes/`.
/// GRDB is used only as a rebuild-able FTS5 search cache.
actor FileBackedNoteRepository: NoteRepositoryProtocol {
    private let notesDirectory: URL
    private let fileService: any NoteFileServiceProtocol
    private let db: any DatabaseServiceProtocol
    private let clock: any AppClock
    private let fileManager: any FileManagerProtocol

    /// In-memory index: NoteID -> (record, file URL).
    private var index: [NoteID: IndexEntry] = [:]
    private var isLoaded = false
    /// Set during writes to suppress file-watcher events from our own changes.
    private(set) var isWriting = false
    /// File-system watcher task — cancelled on stopWatching().
    private var watchTask: Task<Void, Never>?
    private var watcher: (any NoteDirectoryWatcherProtocol)?

    private struct IndexEntry {
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

    // MARK: - Disk Sync

    /// Full scan from disk — used on first load; subsequent changes use `incrementalSync`.
    func reloadFromDisk() async throws {
        let urls = try await fileService.listNoteFiles(in: notesDirectory)
        var newIndex: [NoteID: IndexEntry] = [:]
        for url in urls {
            do {
                let record = try await fileService.readNote(at: url)
                newIndex[record.id] = IndexEntry(record: record, url: url, modificationDate: fileModDate(at: url))
            } catch {
                logger.warning("Skipping malformed note file \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        index = newIndex
        isLoaded = true
    }

    func rebuildCache() async throws {
        try await db.write { database in
            try database.execute(sql: "DELETE FROM notes")
        }
        for entry in index.values {
            try await upsertCache(entry.record)
        }
    }

    /// Incrementally sync index with disk: only reads new/modified files, removes deleted entries.
    private func incrementalSync() async throws {
        let diskURLs = try await fileService.listNoteFiles(in: notesDirectory)
        var diskMap: [String: (url: URL, modDate: Date?)] = [:]
        for url in diskURLs {
            diskMap[url.lastPathComponent] = (url, fileModDate(at: url))
        }

        var indexByFilename: [String: NoteID] = [:]
        for (id, entry) in index {
            indexByFilename[entry.url.lastPathComponent] = id
        }

        // Remove entries whose files no longer exist on disk.
        let removed = Set(indexByFilename.keys).subtracting(diskMap.keys)
        for filename in removed {
            guard let id = indexByFilename[filename] else { continue }
            index[id] = nil
            try await deleteCache(id: id)
        }

        // Read only new or modified files (modDate changed).
        var upsertCount = 0
        for (filename, disk) in diskMap {
            if let id = indexByFilename[filename], let entry = index[id],
               let diskMod = disk.modDate, let indexMod = entry.modificationDate, diskMod == indexMod {
                continue
            }
            do {
                let record = try await fileService.readNote(at: disk.url)
                index[record.id] = IndexEntry(record: record, url: disk.url, modificationDate: disk.modDate)
                try await upsertCache(record)
                upsertCount += 1
            } catch {
                logger.warning("Skipping malformed note file \(filename): \(error.localizedDescription)")
            }
        }
        if !removed.isEmpty || upsertCount > 0 {
            logger.debug("Incremental sync: \(upsertCount) upserted, \(removed.count) removed")
        }
    }

    // MARK: - File Watching

    func startWatching() async throws {
        guard watchTask == nil else { return }
        let watcher = NoteDirectoryWatcher(directoryURL: notesDirectory)
        try await watcher.start()
        self.watcher = watcher
        watchTask = Task { [weak self] in
            guard let self else { return }
            for await _ in watcher.events() {
                guard !Task.isCancelled else { break }
                let writing = await isWriting
                guard !writing else { continue }
                do {
                    try await incrementalSync()
                } catch {
                    logger.error("Failed to sync notes after file change: \(error.localizedDescription)")
                }
            }
        }
    }

    func stopWatching() async {
        watchTask?.cancel()
        watchTask = nil
        await watcher?.stop()
        watcher = nil
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

    private func fileModDate(at url: URL) -> Date? {
        do {
            return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        } catch {
            // Non-critical: modification date is used only for incremental sync optimization.
            logger.debug("Could not read modDate for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func upsertCache(_ note: NoteRecord) async throws {
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

    private func deleteCache(id: NoteID) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM notes WHERE id = ?", arguments: [id.rawValue.uuidString])
        }
    }
}
