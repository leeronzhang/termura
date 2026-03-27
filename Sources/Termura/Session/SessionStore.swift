import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionStore")

@MainActor
final class SessionStore: ObservableObject, SessionStoreProtocol {
    @Published var sessions: [SessionRecord] = []
    @Published var activeSessionID: SessionID?
    /// Set to `true` once persisted sessions have been loaded (or skipped).
    @Published private(set) var hasLoadedPersistedSessions = false
    /// User-visible error message from the last failed operation; cleared on next success.
    @Published var errorMessage: String?
    /// IDs of sessions that were loaded from persistence (restored on launch).
    private(set) var restoredSessionIDs: Set<SessionID> = []

    let engineStore: TerminalEngineStore
    let defaultShell: String?
    /// Project root directory — used as default working directory for new sessions.
    let projectRoot: String?
    let repository: (any SessionRepositoryProtocol)?
    let clock: any AppClock
    var saveTask: Task<Void, Never>?
    /// Tracks in-flight persistence Tasks so they can be awaited during flush.
    var pendingWrites: [Task<Void, Never>] = []

    init(
        engineStore: TerminalEngineStore,
        shell: String? = nil,
        projectRoot: String? = nil,
        repository: (any SessionRepositoryProtocol)? = nil,
        clock: any AppClock = LiveClock()
    ) {
        self.engineStore = engineStore
        defaultShell = shell
        self.projectRoot = projectRoot
        self.repository = repository
        self.clock = clock
    }

    // MARK: - Persistence

    func loadPersistedSessions() async {
        defer { hasLoadedPersistedSessions = true }
        guard let repo = repository else { return }
        do {
            let loaded = try await repo.fetchAll()
            sessions = loaded
            restoredSessionIDs = Set(loaded.map(\.id))
            // Restore the most recently active session, falling back to the first.
            // Only create an engine for the active session — others are created
            // lazily on activation to avoid forking dozens of shells at startup.
            let sorted = loaded.sorted { $0.lastActiveAt > $1.lastActiveAt }
            activeSessionID = sorted.first?.id ?? loaded.first?.id
            if let activeID = activeSessionID {
                engineStore.createEngine(for: activeID, shell: defaultShell, currentDirectory: projectRoot)
            }
            errorMessage = nil
            logger.info("Loaded \(loaded.count) persisted sessions")
        } catch {
            errorMessage = "Failed to load sessions: \(error.localizedDescription)"
            logger.error("Failed to load sessions: \(error)")
        }
    }

    // MARK: - Restored sessions

    func isRestoredSession(id: SessionID) -> Bool {
        restoredSessionIDs.contains(id)
    }

    // MARK: - SessionStoreProtocol

    @discardableResult
    func createSession(title: String? = nil, shell: String? = nil) -> SessionRecord {
        let resolvedShell = shell ?? defaultShell
        let resolvedTitle = title ?? defaultSessionTitle()
        let record = SessionRecord(
            title: resolvedTitle,
            workingDirectory: projectRoot,
            orderIndex: sessions.count
        )
        sessions.append(record)
        engineStore.createEngine(for: record.id, shell: resolvedShell, currentDirectory: projectRoot)
        activeSessionID = record.id
        persistTracked { try await $0.save(record) }
        logger.info("Created session \(record.id) title=\(resolvedTitle)")
        return record
    }

    /// Derives a human-readable session title from the project root directory basename.
    private func defaultSessionTitle() -> String {
        if let root = projectRoot {
            let basename = URL(fileURLWithPath: root).lastPathComponent
            if !basename.isEmpty { return basename }
        }
        return "Terminal"
    }

    func closeSession(id: SessionID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: idx)
        engineStore.terminateEngine(for: id)
        if activeSessionID == id { activeSessionID = sessions.last?.id }
        persistTracked { try await $0.delete(id: id) }
        logger.info("Closed session \(id)")
    }

    func activateSession(id: SessionID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
        ensureEngine(for: id)
    }

    /// Creates a terminal engine for the session if one does not exist yet.
    /// Unlike `activateSession`, does NOT change `activeSessionID`.
    func ensureEngine(for id: SessionID) {
        if engineStore.engine(for: id) == nil {
            engineStore.createEngine(for: id, shell: defaultShell, currentDirectory: projectRoot)
        }
    }

    func renameSession(id: SessionID, title: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].title = TerminalViewModel.stripAgentPrefixes(title)
        let updated = sessions[idx]
        scheduleDebounced { try await $0.save(updated) }
    }

    func updateWorkingDirectory(id: SessionID, path: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].workingDirectory = path
        sessions[idx].lastActiveAt = Date()
        let updated = sessions[idx]
        scheduleDebounced { try await $0.save(updated) }
    }

    func pinSession(id: SessionID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned = true
        let updated = sessions[idx]
        // save() persists the full record including isPinned — no separate setPinned needed.
        persistTracked { try await $0.save(updated) }
    }

    func unpinSession(id: SessionID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned = false
        let updated = sessions[idx]
        persistTracked { try await $0.save(updated) }
    }

    func setAgentType(id: SessionID, type: AgentType) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        guard sessions[idx].agentType != type else { return }
        sessions[idx].agentType = type
        let updated = sessions[idx]
        persistTracked { try await $0.save(updated) }
    }

    func setColorLabel(id: SessionID, label: SessionColorLabel) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].colorLabel = label
        persistTracked { try await $0.setColorLabel(id: id, label: label) }
    }

    func reorderSessions(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
        for index in sessions.indices {
            sessions[index].orderIndex = index
        }
        let ids = sessions.map(\.id)
        persistTracked { try await $0.reorder(ids: ids) }
    }
}
