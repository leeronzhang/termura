import Foundation

/// Observable session store — owns the list of active sessions and selection state.
@MainActor
protocol SessionStoreProtocol: AnyObject {
    var sessions: [SessionRecord] { get }
    var activeSessionID: SessionID? { get }

    @discardableResult
    func createSession(title: String, shell: String) -> SessionRecord
    func closeSession(id: SessionID)
    func activateSession(id: SessionID)
    func renameSession(id: SessionID, title: String)
    func updateWorkingDirectory(id: SessionID, path: String)
    func pinSession(id: SessionID)
    func unpinSession(id: SessionID)
    func setColorLabel(id: SessionID, label: SessionColorLabel)
    func setAgentType(id: SessionID, type: AgentType)
    func reorderSessions(from: IndexSet, to: Int)
    func isRestoredSession(id: SessionID) -> Bool

    // MARK: - Session Tree

    @discardableResult
    func createBranch(from sessionID: SessionID, type: BranchType, title: String) async -> SessionRecord?
    func navigateToParent(of sessionID: SessionID)
    func mergeBranchSummary(branchID: SessionID, summary: String, messageRepo: (any SessionMessageRepositoryProtocol)?) async
}
