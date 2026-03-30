import Combine
import Foundation

/// Observable session store — owns the list of active sessions and selection state.
@MainActor
protocol SessionStoreProtocol: AnyObject, Sendable {
    var sessions: [SessionRecord] { get }
    var activeSessionID: SessionID? { get }
    /// Fires once when persisted sessions have finished loading. Use to gate
    /// startup logic that requires the session list to be populated.
    var sessionsLoaded: AnyPublisher<Void, Never> { get }

    @discardableResult
    func createSession(title: String?, shell: String?) -> SessionRecord
    /// Terminate the PTY and mark session as ended. Record is preserved; session can be reopened.
    func endSession(id: SessionID) async
    /// Permanently delete the session record from the database.
    func deleteSession(id: SessionID) async
    /// Clear ended_at and spawn a new PTY for the session.
    func reopenSession(id: SessionID) async
    func activateSession(id: SessionID)
    func renameSession(id: SessionID, title: String)
    func updateWorkingDirectory(id: SessionID, path: String)
    func pinSession(id: SessionID)
    func unpinSession(id: SessionID)
    func setColorLabel(id: SessionID, label: SessionColorLabel)
    func setAgentType(id: SessionID, type: AgentType)
    func reorderSessions(from: IndexSet, to: Int)
    /// O(1) lookup by session ID. Returns nil if the session does not exist.
    /// Prefer this over scanning `sessions` with `.first(where:)`.
    func session(id: SessionID) -> SessionRecord?
    func isRestoredSession(id: SessionID) -> Bool
    func ensureEngine(for id: SessionID)
    /// Awaits all in-flight persistence Tasks and force-saves debounced state.
    /// Call during app termination or project close to prevent data loss.
    func flushPendingWrites() async

    // MARK: - Session Tree

    func createBranch(from sessionID: SessionID, type: BranchType, title: String?) async
    func navigateToParent(of sessionID: SessionID)
    func mergeBranchSummary(branchID: SessionID, summary: String, messageRepo: (any SessionMessageRepositoryProtocol)?) async
}
