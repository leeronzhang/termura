import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NoteFileService")

// MARK: - Protocol

protocol NoteFileServiceProtocol: Actor {
    func readNote(at url: URL) async throws -> NoteRecord
    func writeNote(_ note: NoteRecord, to directory: URL) async throws -> URL
    func deleteNote(at url: URL) async throws
    func listNoteFiles(in directory: URL) async throws -> [URL]
    func filename(for note: NoteRecord) -> String
}

// MARK: - Implementation

actor NoteFileService: NoteFileServiceProtocol {
    private let fileManager: any FileManagerProtocol

    init(fileManager: any FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

    func readNote(at url: URL) async throws -> NoteRecord {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw NoteFileError.fileReadFailed(path: url.path, underlying: error)
        }
        let decoded = try NoteFrontmatter.decode(from: content)
        var record = NoteRecord(
            id: decoded.id, title: decoded.title, body: decoded.body,
            isFavorite: decoded.isFavorite, references: decoded.references,
            isFolder: decoded.isFolder
        )
        record.createdAt = decoded.createdAt
        record.updatedAt = decoded.updatedAt
        return record
    }

    func writeNote(_ note: NoteRecord, to directory: URL) async throws -> URL {
        let name = filename(for: note)
        let fileURL = directory.appendingPathComponent(name)
        let content = NoteFrontmatter.encode(record: note)

        if note.isFolder {
            let folderURL = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
        }

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw NoteFileError.fileWriteFailed(path: fileURL.path, underlying: error)
        }
        return fileURL
    }

    func deleteNote(at url: URL) async throws {
        let target: URL = if url.lastPathComponent == "README.md" {
            url.deletingLastPathComponent()
        } else {
            url
        }
        do {
            try fileManager.removeItem(at: target)
        } catch {
            logger.error("Failed to delete note at \(target.path): \(error.localizedDescription)")
            throw NoteFileError.fileWriteFailed(path: target.path, underlying: error)
        }
    }

    func listNoteFiles(in directory: URL) async throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var result = contents.filter { $0.pathExtension == "md" }
        let folderNotes = folderNoteURLs(contents: contents)
        result.append(contentsOf: folderNotes)
        return result
    }

    /// Scans subdirectories for folder notes (`subfolder/README.md`).
    private func folderNoteURLs(contents: [URL]) -> [URL] {
        var result: [URL] = []
        for url in contents {
            let isDir: Bool
            do {
                isDir = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            } catch {
                logger.debug("Could not check isDirectory for \(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }
            guard isDir else { continue }
            let readme = url.appendingPathComponent("README.md")
            if fileManager.fileExists(atPath: readme.path) {
                result.append(readme)
            }
        }
        return result
    }

    func filename(for note: NoteRecord) -> String {
        Self.filename(for: note)
    }

    /// Pure-function filename derivation. Exposed as static so callers that only need
    /// the filename string can avoid an actor hop (e.g. NotesViewModel.selectedNoteFilePath).
    /// For folder notes returns `slug/README.md`; for flat notes `{prefix}-{slug}.md`.
    nonisolated static func filename(for note: NoteRecord) -> String {
        if note.isFolder {
            return folderName(for: note) + "/README.md"
        }
        let prefix = String(note.id.rawValue.uuidString.prefix(8)).lowercased()
        let slug = slugify(note.title)
        if slug.isEmpty {
            return "\(prefix).md"
        }
        return "\(prefix)-\(slug).md"
    }

    /// Directory name for a folder note. Uses the same slug logic as flat notes
    /// but without the UUID prefix — folder names are human-readable.
    nonisolated static func folderName(for note: NoteRecord) -> String {
        let slug = slugify(note.title)
        if slug.isEmpty {
            return String(note.id.rawValue.uuidString.prefix(8)).lowercased()
        }
        return slug
    }

    /// Converts a title to a URL-safe slug. Public static so the single canonical
    /// implementation is reusable without duplicating the algorithm elsewhere.
    nonisolated static func slugify(_ title: String) -> String {
        let lowered = title.lowercased()
        var result = ""
        for char in lowered {
            if char.isLetter || char.isNumber {
                result.append(char)
            } else if char == " " || char == "-" || char == "_" {
                if !result.hasSuffix("-") {
                    result.append("-")
                }
            }
        }
        if result.hasSuffix("-") {
            result = String(result.dropLast())
        }
        if result.count > AppConfig.Notes.maxSlugLength {
            result = String(result.prefix(AppConfig.Notes.maxSlugLength))
            if result.hasSuffix("-") {
                result = String(result.dropLast())
            }
        }
        return result
    }
}
