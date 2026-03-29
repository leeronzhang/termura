import Combine
import Foundation

#if DEBUG

/// Mock session store for unit tests and SwiftUI previews.
@Observable
@MainActor
final class MockSessionStore: SessionStoreProtocol {
    private(set) var sessions: [SessionRecord]
    private(set) var activeSessionID: SessionID?

    @ObservationIgnored private(set) var createCallCount = 0
    @ObservationIgnored private(set) var closeCallCount = 0

    @ObservationIgnored private let _sessionsLoaded = PassthroughSubject<Void, Never>()
    var sessionsLoaded: AnyPublisher<Void, Never> { _sessionsLoaded.eraseToAnyPublisher() }

    init(sessions: [SessionRecord] = [], activeID: SessionID? = nil) {
        self.sessions = sessions
        activeSessionID = activeID ?? sessions.first?.id
    }

    @discardableResult
    func createSession(title: String? = nil, shell: String? = nil) -> SessionRecord {
        createCallCount += 1
        let record = SessionRecord(title: title ?? "Terminal", orderIndex: sessions.count)
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

    func ensureEngine(for id: SessionID) {
        // No-op in mock.
    }

    func flushPendingWrites() async {
        // No-op in mock -- no persistence layer.
    }

    // MARK: - Session Tree

    @discardableResult
    func createBranch(from sessionID: SessionID, type: BranchType, title: String? = nil) async -> SessionRecord? {
        let resolvedTitle = title ?? "\(type.rawValue.capitalized) branch"
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

#endif
