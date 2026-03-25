import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "FileTreeService")

/// Scans the project directory and builds a file tree, optionally annotated with git status.
actor FileTreeService {

    /// Scans the directory at `projectRoot` and returns a sorted tree.
    func scan(at projectRoot: String) -> [FileTreeNode] {
        let rootURL = URL(fileURLWithPath: projectRoot)
        return buildChildren(at: rootURL, relativeTo: rootURL, depth: 0)
    }

    /// Annotates tree nodes with git status from a `GitStatusResult`.
    /// Also propagates status up to parent directories.
    func annotate(
        tree: [FileTreeNode],
        with gitResult: GitStatusResult
    ) -> [FileTreeNode] {
        guard gitResult.isGitRepo else { return tree }

        // Build lookup: relativePath → (kind, isStaged)
        var lookup: [String: (GitFileStatus.Kind, Bool)] = [:]
        for file in gitResult.files where lookup[file.path] == nil {
            lookup[file.path] = (file.kind, file.isStaged)
        }

        return annotateNodes(tree, lookup: lookup)
    }

    // MARK: - Private scanning

    private func buildChildren(
        at directoryURL: URL,
        relativeTo rootURL: URL,
        depth: Int
    ) -> [FileTreeNode] {
        guard depth < AppConfig.FileTree.maxDepth else { return [] }

        let fm = FileManager.default
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsPackageDescendants]
            )
        } catch {
            logger.warning("Failed to list directory \(directoryURL.path): \(error.localizedDescription)")
            return []
        }

        var dirs: [FileTreeNode] = []
        var files: [FileTreeNode] = []

        for url in contents {
            let name = url.lastPathComponent

            // Skip hidden files and ignored directories
            if name.hasPrefix(".") && AppConfig.FileTree.ignoredDotfiles { continue }
            if AppConfig.FileTree.ignoredDirectories.contains(name) { continue }

            let isDir: Bool
            do {
                isDir = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            } catch {
                logger.warning("Failed to read resource values for \(url.path): \(error.localizedDescription)")
                isDir = false
            }
            let relativePath = url.path.replacingOccurrences(
                of: rootURL.path + "/",
                with: ""
            )

            if isDir {
                let children = buildChildren(at: url, relativeTo: rootURL, depth: depth + 1)
                dirs.append(FileTreeNode(
                    name: name,
                    relativePath: relativePath,
                    isDirectory: true,
                    children: children
                ))
            } else {
                files.append(FileTreeNode(
                    name: name,
                    relativePath: relativePath,
                    isDirectory: false
                ))
            }
        }

        // Sort: directories first, then files, both alphabetically
        dirs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return dirs + files
    }

    // MARK: - Private annotation

    private func annotateNodes(
        _ nodes: [FileTreeNode],
        lookup: [String: (GitFileStatus.Kind, Bool)]
    ) -> [FileTreeNode] {
        nodes.map { node in
            var annotated = node
            if node.isDirectory, let children = node.children {
                annotated.children = annotateNodes(children, lookup: lookup)
                // Propagate: directory has changes if any child does
                let hasChanges = annotated.children?.contains(where: {
                    $0.gitStatus != nil || ($0.isDirectory && $0.gitStatus != nil)
                }) ?? false
                if hasChanges {
                    annotated.gitStatus = .modified
                }
            } else if let status = lookup[node.relativePath] {
                annotated.gitStatus = status.0
                annotated.isGitStaged = status.1
            }
            return annotated
        }
    }
}
