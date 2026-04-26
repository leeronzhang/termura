import Foundation

/// Resolve a note by title (case-insensitive) or ID prefix fallback.
public func resolveNote(
    title: String,
    lister: NoteFileLister,
    directory: URL
) throws -> (NoteRecord, URL)? {
    if let result = try lister.findNote(byTitle: title, in: directory) {
        return result
    }
    return try lister.findNote(byIDPrefix: title, in: directory)
}
