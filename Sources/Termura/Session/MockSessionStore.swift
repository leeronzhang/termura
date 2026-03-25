import Foundation

/// Mock session store for unit tests and SwiftUI previews.
@MainActor
final class MockSessionStore: ObservableObject, SessionStoreProtocol {
    @Published private(set) var sessions: [SessionRecord]
    @Published private(set) var activeSessionID: SessionID?

    private(set) var createCallCount = 0
    private(set) var closeCallCount = 0

    init(sessions: [SessionRecord] = [], activeID: SessionID? = nil) {
        self.sessions = sessions
        activeSessionID = activeID ?? sessions.first?.id
    }

    @discardableResult
    func createSession(title: String = "Terminal", shell: String = "") -> SessionRecord {
        createCallCount += 1
        let record = SessionRecord(title: title, orderIndex: sessions.count)
        sessions.append(record)
        activeSessionID = record.id
        return record
    }

    func closeSession(id: SessionID) {
        closeCallCount += 1
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = sessions.last?.id
        }
    }

    func activateSession(id: SessionID) {
        activeSessionID = id
    }

    func renameSession(id: SessionID, title: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].title = title
    }

    func updateWorkingDirectory(id: SessionID, path: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].workingDirectory = path
    }

    func pinSession(id: SessionID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned = true
    }

    func unpinSession(id: SessionID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned = false
    }

    func setColorLabel(id: SessionID, label: SessionColorLabel) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].colorLabel = label
    }

    func setAgentType(id: SessionID, type: AgentType) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].agentType = type
    }

    func reorderSessions(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
    }

    func isRestoredSession(id: SessionID) -> Bool {
        false
    }

    // MARK: - Session Tree

    @discardableResult
    func createBranch(from sessionID: SessionID, type: BranchType, title: String = "") async -> SessionRecord? {
        let resolvedTitle = title.isEmpty ? "\(type.rawValue.capitalized) branch" : title
        let record = SessionRecord(title: resolvedTitle, parentID: sessionID, branchType: type)
        sessions.append(record)
        activeSessionID = record.id
        return record
    }

    func navigateToParent(of sessionID: SessionID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }),
              let parentID = sessions[idx].parentID else { return }
        activeSessionID = parentID
    }

    func mergeBranchSummary(branchID: SessionID, summary: String, messageRepo: (any SessionMessageRepositoryProtocol)?) async {
        guard let idx = sessions.firstIndex(where: { $0.id == branchID }),
              let parentID = sessions[idx].parentID else { return }
        sessions[idx].summary = summary
        activeSessionID = parentID
    }
}
