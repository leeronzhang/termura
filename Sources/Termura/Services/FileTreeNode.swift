import Foundation

/// A node in the project file tree. Directories have non-nil `children`.
struct FileTreeNode: Identifiable, Sendable {
    let id: String
    let name: String
    let relativePath: String
    let isDirectory: Bool
    var children: [FileTreeNode]?
    var gitStatus: GitFileStatus.Kind?
    var isGitStaged: Bool

    init(
        name: String,
        relativePath: String,
        isDirectory: Bool,
        children: [FileTreeNode]? = nil,
        gitStatus: GitFileStatus.Kind? = nil,
        isGitStaged: Bool = false
    ) {
        self.id = relativePath.isEmpty ? name : relativePath
        self.name = name
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.children = children
        self.gitStatus = gitStatus
        self.isGitStaged = isGitStaged
    }
}
