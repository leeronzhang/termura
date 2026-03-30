import Foundation

protocol SessionRepositoryProtocol: Actor {
    func fetchAll() async throws -> [SessionRecord]
    func save(_ record: SessionRecord) async throws
    func delete(id: SessionID) async throws
    func archive(id: SessionID) async throws
    func search(query: String) async throws -> [SessionRecord]
    func reorder(ids: [SessionID]) async throws
    func setColorLabel(id: SessionID, label: SessionColorLabel) async throws
    func setPinned(id: SessionID, pinned: Bool) async throws
    /// Mark session as ended (PTY terminated, record preserved). Sets ended_at timestamp.
    func markEnded(id: SessionID, at date: Date) async throws
    /// Clear ended_at, making the session active again.
    func markReopened(id: SessionID) async throws

    // MARK: - Session Tree

    /// Fetch direct children of a parent session.
    func fetchChildren(of parentID: SessionID) async throws -> [SessionRecord]
    /// Fetch the ancestor chain from a session up to the root.
    func fetchAncestors(of sessionID: SessionID) async throws -> [SessionRecord]
    /// Create a new branch session under a parent.
    func createBranch(from parentID: SessionID, type: BranchType, title: String) async throws -> SessionRecord
    /// Update the summary of a completed branch.
    func updateSummary(_ sessionID: SessionID, summary: String) async throws
}
