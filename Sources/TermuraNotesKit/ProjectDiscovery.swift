import Foundation

public enum ProjectDiscoveryError: LocalizedError {
    case notFound

    public var errorDescription: String? {
        "No .termura/ directory found in current or parent directories. Run this command from inside a Termura project."
    }
}

/// Resolves the Termura project root and notes directory paths.
/// `.termura/knowledge/` historically held sources/log/attachments siblings;
/// after the knowledge layer was scoped down to notes-only, only
/// `knowledge/notes/` remains as a meaningful subpath.
public struct ProjectDiscovery: Sendable {
    public let projectRoot: URL
    public let knowledgeRoot: URL
    public let notesDirectory: URL

    /// Walk up from `startURL` until a directory containing `.termura/` is found.
    public init(from startURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws {
        var current = startURL.standardizedFileURL
        let fm = FileManager.default
        while true {
            let candidate = current.appendingPathComponent(".termura")
            if fm.fileExists(atPath: candidate.path) {
                projectRoot = current
                knowledgeRoot = candidate.appendingPathComponent("knowledge")
                notesDirectory = knowledgeRoot.appendingPathComponent("notes")
                return
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { throw ProjectDiscoveryError.notFound }
            current = parent
        }
    }

    /// Ensures the knowledge directory structure exists. Currently only
    /// `knowledge/notes/` is created — sources/log/attachments are not part
    /// of the active layout. Old user data in those legacy paths is left
    /// untouched on disk.
    public func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [notesDirectory] where !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
