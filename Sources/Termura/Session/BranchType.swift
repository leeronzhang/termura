import Foundation

/// Categorizes the purpose of a session branch within a Session Tree.
enum BranchType: String, Sendable, Codable, CaseIterable {
    /// Primary working session (root or unbranched).
    case main
    /// Side branch for investigating an issue.
    case investigation
    /// Side branch for fixing a broken tool or dependency.
    case fix
    /// Side branch for reviewing code changes.
    case review
    /// Side branch for trying an alternative approach before committing.
    case experiment
}
