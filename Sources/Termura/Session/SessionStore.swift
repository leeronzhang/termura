import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionStore")

@Observable
@MainActor
final class SessionStore: SessionStoreProtocol {
    private(set) var sessions: [SessionRecord] = []
    var activeSessionID: SessionID?
    // Cached derived state — rebuilt in a single O(n) pass on every sessions mutation.
    // Views must consume these instead of filtering `sessions` inline (see §3 perf rules).
    private(set) var activeSessions: [SessionRecord] = []
    private(set) var pinnedSessions: [SessionRecord] = []
    private(set) var sessionTreeNodes: [SessionTreeNode] = []
    private(set) var endedSessions: [SessionRecord] = []
    private(set) var sessionTitles: [SessionID: String] = [:]
    /// Current lifecycle state of the store (loading, ready, or failed).
    var state: StoreState = .idle
    /// User-facing error message for persistence or other store-level failures.
    var errorMessage: String?
    /// IDs of sessions that were loaded from persistence (restored on launch).
    @ObservationIgnored private(set) var restoredSessionIDs: Set<SessionID> = []

    let engineStore: TerminalEngineStore
    let defaultShell: String?
    /// Project root directory — used as default working directory for new sessions.
    let projectRoot: String?
    let repository: any SessionRepositoryProtocol
    let clock: any AppClock
    let metricsCollector: (any MetricsCollectorProtocol)? // Optional: observability, nil = no-op
    /// Coordinates all persistence, PTY creation, and debounced metadata updates.
    /// Replaces scattered Task/UUID dictionaries for structural correctness.
    @ObservationIgnored let taskCoordinator = TaskCoordinator()
    /// Fires when a session is fully closed. Subscribers (e.g. SessionViewStateManager)
    /// use this to release per-session resources without a back-reference into SessionStore.
    var sessionDidClose: AnyPublisher<SessionID, Never> { _sessionDidClose.eraseToAnyPublisher() }
    @ObservationIgnored private let _sessionDidClose = PassthroughSubject<SessionID, Never>()
    /// Fires once when persisted sessions have finished loading (or been skipped).
    /// Consumers that need to wait for initial load use this instead of polling
    /// `hasLoadedPersistedSessions` via a Combine publisher.
    var sessionsLoaded: AnyPublisher<Void, Never> { _sessionsLoaded.eraseToAnyPublisher() }
    @ObservationIgnored private let _sessionsLoaded = PassthroughSubject<Void, Never>()
    /// Backward-compatible flag for tests and legacy call sites that only need to know
    /// whether the initial persistence load attempt completed, regardless of success.
    var hasLoadedPersistedSessions: Bool { state != .idle && state != .loading }
    /// O(1) position index: maps SessionID to its position in `sessions`.
    /// Read-only externally; all writes go through `appendSession` or `rebuildSessionIndex`.
    @ObservationIgnored private(set) var sessionIndex: [SessionID: Int] = [:]

    init(
        engineStore: TerminalEngineStore,
        shell: String? = nil,
        projectRoot: String? = nil,
        repository: any SessionRepositoryProtocol,
        clock: any AppClock = LiveClock(),
        metricsCollector: (any MetricsCollectorProtocol)? = nil // Optional: observability, nil = no-op
    ) {
        self.engineStore = engineStore
        defaultShell = shell
        self.projectRoot = projectRoot
        self.repository = repository
        self.clock = clock
        self.metricsCollector = metricsCollector
    }

    func terminateEngineAndWait(for sessionID: SessionID) async {
        await engineStore.terminateEngine(for: sessionID)
    }
}

// MARK: - Persistence

extension SessionStore {
    func loadPersistedSessions() async {
        guard state == .idle else { return }
        state = .loading
        defer { _sessionsLoaded.send() }
        do {
            let loaded = try await repository.fetchAll()
            sessions = loaded
            rebuildSessionIndex()
            restoredSessionIDs = Set(loaded.map(\.id))
            // Restore the most recently active non-ended session, falling back to the first.
            // Only create an engine for the active session — others are created
            // lazily on activation to avoid forking dozens of shells at startup.
            let activeSessions = loaded.filter { !$0.isEnded }
            activeSessionID = activeSessions.max(by: { $0.lastActiveAt < $1.lastActiveAt })?.id
                ?? activeSessions.first?.id
            if let activeID = activeSessionID {
                ensureEngine(for: activeID)
            }
            state = .ready
            logger.info("Loaded \(loaded.count) persisted sessions")
        } catch {
            state = .error(error.localizedDescription)
            logger.error("Failed to load sessions: \(error)")
        }
    }

    func deleteSession(id: SessionID) async {
        // Verify the session exists before touching the DB.
        guard sessionIndex[id] != nil else { return }

        // DB delete first — prevents ghost sessions resurfacing on next launch if we
        // removed from memory first and the delete subsequently failed.
        do {
            try await repository.delete(id: id)
        } catch {
            state = .error("Failed to delete session: \(error.localizedDescription)")
            logger.error("DB delete failed for session \(id): \(error)")
            return
        }

        // Re-check after the await — a concurrent operation may have already removed it.
        guard let idx = sessionIndex[id] else { return }
        sessions.remove(at: idx)
        rebuildSessionIndex()
        await engineStore.terminateEngine(for: id)
        if activeSessionID == id { activeSessionID = sessions.last(where: { !$0.isEnded })?.id }
        restoredSessionIDs.remove(id)
        _sessionDidClose.send(id)
        logger.info("Deleted session \(id)")
        if let collector = metricsCollector {
            let activeCount = sessions.count
            Task { await collector.incrementAndSetGauge(.sessionClosed, gauge: .activeSessions, value: Double(activeCount)) }
        }
    }

    func activateSession(id: SessionID) {
        let start = ContinuousClock.now
        guard sessionIndex[id] != nil else { return }
        activeSessionID = id
        if engineStore.engine(for: id) != nil {
            // Engine already alive — zero-cost switch, record metric immediately.
            let elapsed = ContinuousClock.now - start
            if let collector = metricsCollector {
                Task { await collector.recordDuration(.sessionSwitchDuration, seconds: elapsed.totalSeconds) }
            }
        } else {
            // No engine yet: debounce PTY fork so rapid sidebar clicks don't spawn N shells.
            // Only the final session the user lands on will call fork/exec.
            taskCoordinator.debounce(
                key: "engine-ensure",
                delay: AppConfig.Runtime.engineCreationDebounce,
                clock: clock
            ) { [weak self] in
                guard let self, activeSessionID == id else { return }
                ensureEngine(for: id)
                let elapsed = ContinuousClock.now - start
                if let collector = metricsCollector {
                    Task { await collector.recordDuration(.sessionSwitchDuration, seconds: elapsed.totalSeconds) }
                }
            }
        }
    }

    /// Awaits the current engine-creation debounce task, if any.
    func waitForEngineActivationIdle() async {
        await taskCoordinator.waitForIdle()
    }
}

// MARK: - Internal mutation helpers

// Same-file extension: retains private(set) setter access to `sessions` and `sessionIndex`
// without expanding the class body beyond the type_body_length limit.
extension SessionStore {
    /// Rebuilds the full position index from `sessions`, then refreshes all derived state.
    /// O(n) — call only after structural mutations (bulk load, removal, reorder).
    func rebuildSessionIndex() {
        sessionIndex.removeAll(keepingCapacity: true)
        for (i, session) in sessions.enumerated() {
            sessionIndex[session.id] = i
        }
        rebuildDerivedState()
        rebuildSessionTitles()
    }

    /// Appends a session record, updates the O(1) position index, and refreshes derived state.
    func appendSession(_ record: SessionRecord) {
        sessions.append(record)
        sessionIndex[record.id] = sessions.count - 1
        sessionTitles[record.id] = record.title
        rebuildDerivedState()
    }

    /// Mutates a session in place by ID, then refreshes derived state.
    /// Returns the updated record, or nil if not found.
    @discardableResult
    func mutateSession(id: SessionID, _ update: (inout SessionRecord) -> Void) -> SessionRecord? {
        guard let idx = sessionIndex[id] else { return nil }
        update(&sessions[idx])
        // O(1) incremental title update — rebuildDerivedState never touches sessionTitles.
        sessionTitles[id] = sessions[idx].title
        rebuildDerivedState()
        return sessions[idx]
    }

    /// Reorders the sessions array in place and rebuilds the index.
    func reorderSessionsInPlace(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
        for index in sessions.indices {
            sessions[index].orderIndex = index
        }
        rebuildSessionIndex()
    }

    /// Replaces all sessions and rebuilds the index. Use only for rollback in onFailure closures.
    func replaceAllSessions(_ newSessions: [SessionRecord]) {
        sessions = newSessions
        rebuildSessionIndex()
    }

    /// Single O(n) pass over `sessions` that refreshes the filtered derived arrays.
    /// Does NOT touch `sessionTitles` — title maintenance is a separate responsibility:
    ///   - In-place mutations: caller writes `sessionTitles[id] = ...` directly (O(1)).
    ///   - Structural mutations: `rebuildSessionIndex` calls `rebuildSessionTitles()` after this.
    func rebuildDerivedState() {
        var active: [SessionRecord] = []
        var pinned: [SessionRecord] = []
        var activeTree: [SessionRecord] = []
        var ended: [SessionRecord] = []
        for session in sessions {
            if session.isEnded {
                ended.append(session)
            } else {
                active.append(session)
                if session.isPinned { pinned.append(session) } else { activeTree.append(session) }
            }
        }
        activeSessions = active
        pinnedSessions = pinned
        sessionTreeNodes = SessionTreeNode.buildForest(from: activeTree)
        endedSessions = ended
    }

    /// Full O(n) rebuild of `sessionTitles`.
    /// Called only from `rebuildSessionIndex` (structural mutations: delete, reorder, bulk replace).
    /// In-place mutations skip this and update the affected entry directly.
    private func rebuildSessionTitles() {
        var titles: [SessionID: String] = [:]
        titles.reserveCapacity(sessions.count)
        for session in sessions {
            titles[session.id] = session.title
        }
        sessionTitles = titles
    }
}

/// Lifecycle state for the SessionStore initialization.
enum StoreState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case error(String)
}
