import Foundation

/// Lightweight note file operations (no actor, no DI — uses FileManager.default).
public struct NoteFileLister: Sendable {
    private static let maxSlugLength = 50

    public init() {}

    // MARK: - Read

    public func listNotes(in directory: URL) throws -> [NoteRecord] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let urls = try noteFileURLs(in: directory)
        var notes: [NoteRecord] = []
        for url in urls {
            do {
                try notes.append(readNote(at: url))
            } catch {
                // Non-critical: skip malformed notes, log to stderr
                FileHandle.standardError.write(
                    Data("warning: skipping \(url.lastPathComponent): \(error.localizedDescription)\n".utf8)
                )
            }
        }
        return notes.sorted(by: NoteRecord.displayOrder)
    }

    public func readNote(at url: URL) throws -> NoteRecord {
        let content = try String(contentsOf: url, encoding: .utf8)
        let decoded = try NoteFrontmatter.decode(from: content)
        var record = NoteRecord(
            id: decoded.id, title: decoded.title, body: decoded.body,
            isFavorite: decoded.isFavorite, tags: decoded.tags,
            references: decoded.references, isFolder: decoded.isFolder
        )
        record.createdAt = decoded.createdAt
        record.updatedAt = decoded.updatedAt
        return record
    }

    // MARK: - Write

    public func writeNote(_ note: NoteRecord, to directory: URL) throws -> URL {
        let name = Self.filename(for: note)
        let fileURL = directory.appendingPathComponent(name)
        let fm = FileManager.default

        if note.isFolder {
            let folderURL = fileURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: folderURL.path) {
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            }
        }

        let content = NoteFrontmatter.encode(record: note)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Search

    public func searchNotes(query: String, in directory: URL) throws -> [(note: NoteRecord, matches: [String])] {
        let notes = try listNotes(in: directory)
        let lowered = query.lowercased()
        var results: [(note: NoteRecord, matches: [String])] = []
        for note in notes {
            var matchLines: [String] = []
            if note.title.lowercased().contains(lowered) {
                matchLines.append("title: \(note.title)")
            }
            let bodyLines = note.body.components(separatedBy: "\n")
            for line in bodyLines where line.lowercased().contains(lowered) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    matchLines.append(String(trimmed.prefix(120)))
                }
            }
            if !matchLines.isEmpty {
                results.append((note: note, matches: matchLines))
            }
        }
        return results
    }

    // MARK: - Find

    public func findNote(byTitle title: String, in directory: URL) throws -> (NoteRecord, URL)? {
        let urls = try noteFileURLs(in: directory)
        for url in urls {
            let note = try readNote(at: url)
            if note.title.caseInsensitiveCompare(title) == .orderedSame {
                return (note, url)
            }
        }
        return nil
    }

    public func findNote(byIDPrefix prefix: String, in directory: URL) throws -> (NoteRecord, URL)? {
        let urls = try noteFileURLs(in: directory)
        let lowered = prefix.lowercased()
        for url in urls {
            let note = try readNote(at: url)
            if note.id.rawValue.uuidString.lowercased().hasPrefix(lowered) {
                return (note, url)
            }
        }
        return nil
    }

    // MARK: - Private

    private func noteFileURLs(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var urls = contents.filter { $0.pathExtension == "md" }
        for url in contents {
            let isDir: Bool
            do {
                isDir = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            } catch {
                continue
            }
            guard isDir else { continue }
            let readme = url.appendingPathComponent("README.md")
            if fm.fileExists(atPath: readme.path) {
                urls.append(readme)
            }
        }
        return urls
    }

    public static func filename(for note: NoteRecord) -> String {
        if note.isFolder {
            return folderName(for: note) + "/README.md"
        }
        let prefix = String(note.id.rawValue.uuidString.prefix(8)).lowercased()
        let slug = slugify(note.title)
        return slug.isEmpty ? "\(prefix).md" : "\(prefix)-\(slug).md"
    }

    private static func folderName(for note: NoteRecord) -> String {
        let slug = slugify(note.title)
        return slug.isEmpty ? String(note.id.rawValue.uuidString.prefix(8)).lowercased() : slug
    }

    public static func slugify(_ title: String) -> String {
        var result = ""
        for char in title.lowercased() {
            if char.isLetter || char.isNumber {
                result.append(char)
            } else if char == " " || char == "-" || char == "_" {
                if !result.hasSuffix("-") { result.append("-") }
            }
        }
        if result.hasSuffix("-") { result = String(result.dropLast()) }
        if result.count > maxSlugLength {
            result = String(result.prefix(maxSlugLength))
            if result.hasSuffix("-") { result = String(result.dropLast()) }
        }
        return result
    }
}
