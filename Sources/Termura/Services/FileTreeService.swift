import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "FileTreeService")

// MARK: - FileTreeServiceProtocol

protocol FileTreeServiceProtocol: Actor {
    func scan(at projectRoot: String) -> [FileTreeNode]
    func annotate(
        tree: [FileTreeNode],
        with gitResult: GitStatusResult,
        trackedFiles: Set<String>
    ) -> [FileTreeNode]
}

// MARK: - FileTreeService

/// Scans the project directory and builds a file tree, optionally annotated with git status.
actor FileTreeService: FileTreeServiceProtocol {
    private let fileManager: any FileManagerProtocol

    init(fileManager: any FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

    /// macOS TCC-protected directories under home that trigger permission popups.
    /// Skipped when scanning the home directory to avoid repeated system dialogs.
    private static let tccProtectedDirectories: Set<String> = [
        "Library", "Pictures", "Movies", "Music",
        "Applications", "Desktop", "Documents", "Downloads",
        "Public", "Contacts", "Calendars"
    ]

    /// Scans the directory at `projectRoot` and returns a sorted tree.
    func scan(at projectRoot: String) -> [FileTreeNode] {
        let rootURL = URL(fileURLWithPath: projectRoot)
        return buildChildren(at: rootURL, relativeTo: rootURL, depth: 0)
    }

    /// Annotates tree nodes with git status from a `GitStatusResult`.
    /// Also propagates status up to parent directories and marks ignored files.
    func annotate(
        tree: [FileTreeNode],
        with gitResult: GitStatusResult,
        trackedFiles: Set<String> = []
    ) -> [FileTreeNode] {
        guard gitResult.isGitRepo else { return tree }

        // Build lookup: relativePath → (kind, isStaged)
        var lookup: [String: (GitFileStatus.Kind, Bool)] = [:]
        for file in gitResult.files where lookup[file.path] == nil {
            lookup[file.path] = (file.kind, file.isStaged)
        }

        return annotateNodes(tree, lookup: lookup, trackedFiles: trackedFiles)
    }

    // MARK: - Private scanning

    private func buildChildren(
        at directoryURL: URL,
        relativeTo rootURL: URL,
        depth: Int
    ) -> [FileTreeNode] {
        guard depth < AppConfig.FileTree.maxDepth else { return [] }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsPackageDescendants]
            )
        } catch {
            logger.warning("Failed to list directory \(directoryURL.path): \(error.localizedDescription)")
            return []
        }

        let (dirURLs, fileURLs) = classifyEntries(contents, relativeTo: rootURL)
        var dirs = dirURLs.map { entry in
            let children = buildChildren(at: entry.url, relativeTo: rootURL, depth: depth + 1)
            return FileTreeNode(name: entry.name, relativePath: entry.relativePath, isDirectory: true, children: children)
        }
        var files = fileURLs.map { entry in
            FileTreeNode(name: entry.name, relativePath: entry.relativePath, isDirectory: false)
        }

        dirs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return dirs + files
    }

    private struct ClassifiedEntry {
        let url: URL
        let name: String
        let relativePath: String
    }

    /// Classifies directory contents into directories and files, filtering out hidden/ignored entries.
    private func classifyEntries(
        _ contents: [URL],
        relativeTo rootURL: URL
    ) -> (dirs: [ClassifiedEntry], files: [ClassifiedEntry]) {
        var dirs: [ClassifiedEntry] = []
        var files: [ClassifiedEntry] = []

        for url in contents {
            let name = url.lastPathComponent
            if name.hasPrefix(".") && AppConfig.FileTree.ignoredDotfiles { continue }
            if AppConfig.FileTree.ignoredDirectories.contains(name) { continue }
            if Self.tccProtectedDirectories.contains(name),
               url.deletingLastPathComponent().path == AppConfig.Paths.homeDirectory { continue }

            let isDir: Bool
            do {
                isDir = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            } catch {
                logger.warning("Failed to read resource values for \(url.path): \(error.localizedDescription)")
                isDir = false
            }
            let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
            let relativePath = url.path.replacingOccurrences(of: rootPrefix, with: "")
            let entry = ClassifiedEntry(url: url, name: name, relativePath: relativePath)

            if isDir {
                dirs.append(entry)
            } else {
                files.append(entry)
            }
        }
        return (dirs, files)
    }

    // MARK: - Private annotation

    private func annotateNodes(
        _ nodes: [FileTreeNode],
        lookup: [String: (GitFileStatus.Kind, Bool)],
        trackedFiles: Set<String>
    ) -> [FileTreeNode] {
        nodes.map { node in
            var annotated = node
            if node.isDirectory, let children = node.children {
                annotated.children = annotateNodes(
                    children, lookup: lookup, trackedFiles: trackedFiles
                )
                // Aggregate git stats from all descendants
                var stats: [GitFileStatus.Kind: Int] = [:]
                for child in annotated.children ?? [] {
                    if child.isDirectory {
                        // Merge child directory's aggregated stats
                        for (kind, count) in child.gitChildStats {
                            stats[kind, default: 0] += count
                        }
                    } else if let kind = child.gitStatus {
                        stats[kind, default: 0] += 1
                    }
                }
                annotated.gitChildStats = stats
                if !stats.isEmpty {
                    annotated.gitStatus = .modified
                }
                // Directory is ignored if ALL children are ignored
                let allIgnored = annotated.children?.allSatisfy(\.isGitIgnored) ?? false
                if allIgnored && !(annotated.children?.isEmpty ?? true) {
                    annotated.isGitIgnored = true
                }
            } else if let status = lookup[node.relativePath] {
                annotated.gitStatus = status.0
                annotated.isGitStaged = status.1
            } else if !trackedFiles.isEmpty
                && !trackedFiles.contains(node.relativePath) {
                // File has no git status and is not tracked → ignored
                annotated.isGitIgnored = true
            }
            return annotated
        }
    }
}
