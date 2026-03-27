import Foundation

/// Status of a single file in the git working tree.
struct GitFileStatus: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable {
        case modified, added, deleted, renamed, copied, untracked
    }

    var id: String { path }
    let path: String
    let kind: Kind
    let isStaged: Bool
}

/// Snapshot of `git status` for a project directory.
struct GitStatusResult: Sendable {
    let branch: String
    let files: [GitFileStatus]
    let isGitRepo: Bool
    /// Commits ahead of the tracking branch.
    let ahead: Int
    /// Commits behind the tracking branch.
    let behind: Int
    /// Most recent commit (short hash + subject), nil if no commits yet.
    var lastCommit: String?
    /// Short remote host label (e.g. "GitHub", "GitLab"), nil if no remote.
    var remoteHost: String?

    static let notARepo = GitStatusResult(
        branch: "", files: [], isGitRepo: false, ahead: 0, behind: 0
    )

    var stagedFiles: [GitFileStatus] { files.filter(\.isStaged) }
    var modifiedFiles: [GitFileStatus] { files.filter { !$0.isStaged && $0.kind != .untracked } }
    var untrackedFiles: [GitFileStatus] { files.filter { $0.kind == .untracked } }

    var stagedCount: Int { stagedFiles.count }
    var modifiedCount: Int { modifiedFiles.count }
    var untrackedCount: Int { untrackedFiles.count }
}
