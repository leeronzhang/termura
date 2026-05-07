import Foundation
@testable import Termura

/// Test double for NoteFileServiceProtocol.
/// Stores notes in-memory and supports error injection for specific NoteIDs.
actor MockNoteFileService: NoteFileServiceProtocol {
    /// In-memory file store: URL -> NoteRecord.
    var writtenNotes: [URL: NoteRecord] = [:]
    /// NoteIDs that should trigger a write failure.
    var failingWriteIDs: Set<NoteID> = []
    /// NoteIDs that should trigger a delete failure.
    var failingDeleteIDs: Set<NoteID> = []
    /// URLs that should trigger a delete failure.
    var failingDeleteURLs: Set<URL> = []
    /// URLs that should trigger a read failure.
    var failingReadURLs: Set<URL> = []

    func readNote(at url: URL) async throws -> NoteRecord {
        if failingReadURLs.contains(url) {
            throw NoteFileError.fileReadFailed(path: url.path, underlying: CocoaError(.fileReadNoPermission))
        }
        guard let note = writtenNotes[url] else {
            throw NoteFileError.fileReadFailed(path: url.path, underlying: CocoaError(.fileNoSuchFile))
        }
        return note
    }

    func writeNote(_ note: NoteRecord, to directory: URL) async throws -> URL {
        if failingWriteIDs.contains(note.id) {
            throw NoteFileError.fileWriteFailed(
                path: directory.appendingPathComponent(filename(for: note)).path,
                underlying: CocoaError(.fileWriteNoPermission)
            )
        }
        let url = directory.appendingPathComponent(filename(for: note))
        writtenNotes[url] = note
        return url
    }

    func deleteNote(at url: URL) async throws {
        if failingDeleteURLs.contains(url) {
            throw NoteFileError.fileWriteFailed(path: url.path, underlying: CocoaError(.fileNoSuchFile))
        }
        writtenNotes.removeValue(forKey: url)
    }

    func listNoteFiles(in directory: URL) async throws -> [URL] {
        let dirPath = directory.standardizedFileURL.path
        return writtenNotes.keys.filter { url in
            let filePath = url.standardizedFileURL.path
            guard filePath.hasPrefix(dirPath) else { return false }
            // Include flat notes (direct children) and folder notes (one level deep README.md).
            let relative = String(filePath.dropFirst(dirPath.count + 1))
            let depth = relative.components(separatedBy: "/").count
            return depth <= 2
        }
    }

    func filename(for note: NoteRecord) -> String {
        NoteFileService.filename(for: note)
    }
}
