import Combine
import Foundation

#if DEBUG

/// Debug session store for SwiftUI previews.
@Observable
@MainActor
final class DebugSessionStore: SessionStoreProtocol {
    private(set) var sessions: [SessionRecord]
    private(set) var activeSessionID: SessionID?
    var projectRoot: String?
    // Cached derived state — mirrors SessionStore for protocol conformance.
    private(set) var activeSessions: [SessionRecord] = []
    private(set) var pinnedSessions: [SessionRecord] = []
    private(set) var sessionTreeNodes: [SessionTreeNode] = []
    private(set) var endedSessions: [SessionRecord] = []
    private(set) var sessionTitles: [SessionID: String] = [:]

    @ObservationIgnored private(set) var createCallCount = 0
    @ObservationIgnored private(set) var deleteCallCount = 0
    @ObservationIgnored private var sessionIndex: [SessionID: Int] = [:]

    @ObservationIgnored private let _sessionsLoaded = PassthroughSubject<Void, Never>()
    var sessionsLoaded: AnyPublisher<Void, Never> { _sessionsLoaded.eraseToAnyPublisher() }

    init(sessions: [SessionRecord] = [], activeID: SessionID? = nil) {
        self.sessions = sessions
        activeSessionID = activeID ?? sessions.first?.id
        for (i, s) in sessions.enumerated() {
            sessionIndex[s.id] = i
        }
        // didSet does not fire during init; populate derived state explicitly.
        rebuildDerivedState()
    }

    private func rebuildSessionIndex() {
        sessionIndex.removeAll(keepingCapacity: true)
        for (i, session) in sessions.enumerated() {
            sessionIndex[session.id] = i
        }
        rebuildDerivedState()
        rebuildSessionTitles()
    }

    /// Refreshes the filtered derived arrays. Does NOT touch `sessionTitles`.
    /// Mirrors SessionStore.rebuildDerivedState — same ownership contract applies.
    private func rebuildDerivedState() {
        var active: [SessionRecord] = []
        var pinned: [SessionRecord] = []
        var activeTree: [SessionRecord] = []
        var ended: [SessionRecord] = []
        for session in sessions {
            if session.isEnded {
                ended.append(session)
            } else {
                active.append(session)
                if session.isPinned {
                    pinned.append(session)
                } else {
                    activeTree.append(session)
                }
            }
        }
        activeSessions = active
        pinnedSessions = pinned
        sessionTreeNodes = SessionTreeNode.buildForest(from: activeTree)
        endedSessions = ended
    }

    private func rebuildSessionTitles() {
        var titles: [SessionID: String] = [:]
        titles.reserveCapacity(sessions.count)
        for session in sessions {
            titles[session.id] = session.title
        }
        sessionTitles = titles
    }

    @discardableResult
    func createSession(title: String? = nil, shell: String? = nil) -> SessionRecord {
        createCallCount += 1
        let record = SessionRecord(title: title ?? "Terminal", orderIndex: sessions.count)
        sessions.append(record)
        sessionIndex[record.id] = sessions.count - 1
        activeSessionID = record.id
        sessionTitles[record.id] = record.title
        rebuildDerivedState()
        return record
    }

    func endSession(id: SessionID) async {
        guard let idx = sessionIndex[id], !sessions[idx].isEnded else { return }
        sessions[idx].status = .ended(at: Date())
        if activeSessionID == id {
            activeSessionID = sessions.last(where: { !$0.isEnded })?.id
        }
        rebuildDerivedState()
    }

    func reopenSession(id: SessionID) async {
        guard let idx = sessionIndex[id], sessions[idx].isEnded else { return }
        sessions[idx].status = .active
        activeSessionID = id
        rebuildDerivedState()
    }

    func deleteSession(id: SessionID) async {
        deleteCallCount += 1
        guard let idx = sessionIndex[id] else { return }
        sessions.remove(at: idx)
        rebuildSessionIndex()
        if activeSessionID == id {
            activeSessionID = sessions.last(where: { !$0.isEnded })?.id
        }
    }

    func activateSession(id: SessionID) {
        activeSessionID = id
    }

    func renameSession(id: SessionID, title: String) {
        guard let idx = sessionIndex[id] else { return }
        sessions[idx].title = title
        sessionTitles[id] = title
        rebuildDerivedState()
    }

    func updateWorkingDirectory(id: SessionID, path: String) {
        guard let idx = sessionIndex[id] else { return }
        sessions[idx].workingDirectory = path
    }

    func pinSession(id: SessionID) {
        guard let idx = sessionIndex[id] else { return }
        sessions[idx].isPinned = true
        rebuildDerivedState()
    }

    func unpinSession(id: SessionID) {
        guard let idx = sessionIndex[id] else { return }
        sessions[idx].isPinned = false
        rebuildDerivedState()
    }

    func setColorLabel(id: SessionID, label: SessionColorLabel) {
        guard let idx = sessionIndex[id] else { return }
        sessions[idx].colorLabel = label
    }

    func setAgentType(id: SessionID, type: AgentType) {
        guard let idx = sessionIndex[id] else { return }
        sessions[idx].agentType = type
    }

    func reorderSessions(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
        for index in sessions.indices {
            sessions[index].orderIndex = index
        }
        rebuildSessionIndex()
    }

    func session(id: SessionID) -> SessionRecord? {
        guard let idx = sessionIndex[id] else { return nil }
        return sessions[idx]
    }

    func isRestoredSession(id: SessionID) -> Bool {
        false
    }

    func ensureEngine(for id: SessionID, shell: String?) {
        // No-op in mock.
    }

    func flushPendingWrites() async {
        // No-op in mock -- no persistence layer.
    }

    // MARK: - Session Tree

    func createBranch(from sessionID: SessionID, type: BranchType, title: String? = nil) async {
        let resolvedTitle = title ?? "\(type.rawValue.capitalized) branch"
        let record = SessionRecord(title: resolvedTitle, parentID: sessionID, branchType: type)
        sessions.append(record)
        sessionIndex[record.id] = sessions.count - 1
        activeSessionID = record.id
        sessionTitles[record.id] = record.title
        rebuildDerivedState()
    }

    func navigateToParent(of sessionID: SessionID) {
        guard let idx = sessionIndex[sessionID],
              let parentID = sessions[idx].parentID else { return }
        activeSessionID = parentID
    }

    func mergeBranchSummary(branchID: SessionID, summary: String, messageRepo: (any SessionMessageRepositoryProtocol)?) async {
        guard let idx = sessionIndex[branchID],
              let parentID = sessions[idx].parentID else { return }
        sessions[idx].summary = summary
        activeSessionID = parentID
    }
}

#endif
