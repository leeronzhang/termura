import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "FileBackedNoteRepository.DiskSync")

extension FileBackedNoteRepository {
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
    /// Uses relative paths as keys to avoid collisions between folder notes (all named README.md).
    func incrementalSync() async throws {
        let diskURLs = try await fileService.listNoteFiles(in: notesDirectory)
        var diskMap: [String: (url: URL, modDate: Date?)] = [:]
        for url in diskURLs {
            diskMap[relativeKey(for: url)] = (url, fileModDate(at: url))
        }

        var indexByRelPath: [String: NoteID] = [:]
        for (id, entry) in index {
            indexByRelPath[relativeKey(for: entry.url)] = id
        }

        // Remove entries whose files no longer exist on disk.
        let removed = Set(indexByRelPath.keys).subtracting(diskMap.keys)
        for relPath in removed {
            guard let id = indexByRelPath[relPath] else { continue }
            index[id] = nil
            try await deleteCache(id: id)
        }

        // Read only new or modified files (modDate changed).
        var upsertCount = 0
        for (relPath, disk) in diskMap {
            if let id = indexByRelPath[relPath], let entry = index[id],
               let diskMod = disk.modDate, let indexMod = entry.modificationDate, diskMod == indexMod {
                continue
            }
            do {
                let record = try await fileService.readNote(at: disk.url)
                index[record.id] = IndexEntry(record: record, url: disk.url, modificationDate: disk.modDate)
                try await upsertCache(record)
                upsertCount += 1
            } catch {
                logger.warning("Skipping malformed note file \(relPath): \(error.localizedDescription)")
            }
        }
        if !removed.isEmpty || upsertCount > 0 {
            logger.debug("Incremental sync: \(upsertCount) upserted, \(removed.count) removed")
        }
    }

    /// Returns a path relative to `notesDirectory`, e.g. `my-topic/README.md` or `abc-note.md`.
    private func relativeKey(for url: URL) -> String {
        let base = notesDirectory.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        if full.hasPrefix(base) {
            let rel = String(full.dropFirst(base.count))
            return rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
        }
        return url.lastPathComponent
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
}
