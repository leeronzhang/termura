import Foundation

public enum ProjectDiscoveryError: LocalizedError {
    case notFound

    public var errorDescription: String? {
        "No .termura/ directory found in current or parent directories. Run this command from inside a Termura project."
    }
}

/// Resolves the Termura project root and knowledge directory paths.
public struct ProjectDiscovery: Sendable {
    public let projectRoot: URL
    public let knowledgeRoot: URL
    public let notesDirectory: URL
    public let sourcesDirectory: URL
    public let logDirectory: URL
    public let attachmentsDirectory: URL

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
                sourcesDirectory = knowledgeRoot.appendingPathComponent("sources")
                logDirectory = knowledgeRoot.appendingPathComponent("log")
                attachmentsDirectory = knowledgeRoot.appendingPathComponent("attachments")
                return
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { throw ProjectDiscoveryError.notFound }
            current = parent
        }
    }

    /// Ensures the knowledge directory structure exists, creating missing subdirectories.
    public func ensureDirectories() throws {
        let fm = FileManager.default
        let dirs = [notesDirectory, sourcesDirectory, logDirectory, attachmentsDirectory,
                    sourcesDirectory.appendingPathComponent("articles"),
                    sourcesDirectory.appendingPathComponent("papers"),
                    sourcesDirectory.appendingPathComponent("images"),
                    sourcesDirectory.appendingPathComponent("code"),
                    sourcesDirectory.appendingPathComponent("data")]
        for dir in dirs where !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
