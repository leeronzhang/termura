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
    /// Set to `true` once persisted sessions have been loaded (or skipped).
    private(set) var hasLoadedPersistedSessions = false
    /// User-visible error message from the last failed operation; cleared on next success.
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
    /// Per-operation persistence debounce slots, keyed by "<operation>-<sessionID>"
    /// so that concurrent rename/workingDirectory updates for the same session never
    /// cancel each other. Only used by `scheduleDebounced` and `flushPendingWrites`.
    /// Engine-creation debounce uses the dedicated `engineEnsureTask` below.
    @ObservationIgnored var debounceTasks: [String: Task<Void, Never>] = [:]
    /// Single-slot debounce for lazy PTY creation on `activateSession`.
    ///
    /// IMPORTANT: this MUST remain a single Task property (not keyed by session ID).
    /// Rapid sidebar clicks cancel the previous pending fork so only the session the
    /// user finally lands on spawns a shell. Changing this to a per-session key
    /// (e.g. "engine-ensure-\(id)") would allow N concurrent PTY forks — do not do that.
    @ObservationIgnored var engineEnsureTask: Task<Void, Never>?
    /// Tracks in-flight persistence Tasks so they can be awaited during flush.
    /// Keyed by UUID so each Task can remove itself upon completion (self-pruning).
    @ObservationIgnored var pendingWrites: [UUID: Task<Void, Never>] = [:]
    /// Fires when a session is fully closed. Subscribers (e.g. SessionViewStateManager)
    /// use this to release per-session resources without a back-reference into SessionStore.
    var sessionDidClose: AnyPublisher<SessionID, Never> { _sessionDidClose.eraseToAnyPublisher() }
    @ObservationIgnored private let _sessionDidClose = PassthroughSubject<SessionID, Never>()
    /// Fires once when persisted sessions have finished loading (or been skipped).
    /// Consumers that need to wait for initial load use this instead of polling
    /// `hasLoadedPersistedSessions` via a Combine publisher.
    var sessionsLoaded: AnyPublisher<Void, Never> { _sessionsLoaded.eraseToAnyPublisher() }
    @ObservationIgnored private let _sessionsLoaded = PassthroughSubject<Void, Never>()
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

    deinit {
        engineEnsureTask?.cancel()
        debounceTasks.values.forEach { $0.cancel() }
        pendingWrites.values.forEach { $0.cancel() }
    }
}

// MARK: - Persistence

extension SessionStore {

    func loadPersistedSessions() async {
        guard !hasLoadedPersistedSessions else { return }
        defer {
            hasLoadedPersistedSessions = true
            _sessionsLoaded.send()
        }
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
                engineStore.createEngine(for: activeID, shell: defaultShell, currentDirectory: projectRoot)
            }
            errorMessage = nil
            logger.info("Loaded \(loaded.count) persisted sessions")
        } catch {
            errorMessage = "Failed to load sessions: \(error.localizedDescription)"
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
            errorMessage = "Failed to delete session: \(error.localizedDescription)"
            logger.error("DB delete failed for session \(id): \(error)")
            return
        }

        // Re-check after the await — a concurrent operation may have already removed it.
        guard let idx = sessionIndex[id] else { return }
        sessions.remove(at: idx)
        rebuildSessionIndex()
        engineStore.terminateEngine(for: id)
        if activeSessionID == id { activeSessionID = sessions.last(where: { !$0.isEnded })?.id }
        restoredSessionIDs.remove(id)
        _sessionDidClose.send(id)
        logger.info("Deleted session \(id)")
        if let collector = metricsCollector {
            let activeCount = sessions.count
            Task {
                await collector.increment(.sessionClosed)
                await collector.gauge(.activeSessions, value: Double(activeCount))
            }
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
            engineEnsureTask?.cancel()
            engineEnsureTask = Task { [weak self] in // inherits @MainActor from SessionStore context
                guard let self else { return }
                do {
                    try await Task.sleep(for: AppConfig.Runtime.engineCreationDebounce)
                } catch {
                    // Task.sleep only throws CancellationError; treat any error as cancellation.
                    return
                }
                guard activeSessionID == id else { return }
                self.ensureEngine(for: id)
                let elapsed = ContinuousClock.now - start
                if let collector = self.metricsCollector {
                    Task { await collector.recordDuration(.sessionSwitchDuration, seconds: elapsed.totalSeconds) }
                }
            }
        }
    }
}

// MARK: - Internal mutation helpers
// Same-file extension: retains private(set) setter access to `sessions` and `sessionIndex`
// without expanding the class body beyond the type_body_length limit.
extension SessionStore {

    /// Rebuilds the full position index from `sessions`, then refreshes derived state.
    /// O(n) — call only after structural mutations (bulk load, removal, reorder).
    func rebuildSessionIndex() {
        sessionIndex.removeAll(keepingCapacity: true)
        for (i, session) in sessions.enumerated() {
            sessionIndex[session.id] = i
        }
        rebuildDerivedState()
    }

    /// Appends a session record, updates the O(1) position index, and refreshes derived state.
    func appendSession(_ record: SessionRecord) {
        sessions.append(record)
        sessionIndex[record.id] = sessions.count - 1
        rebuildDerivedState()
    }

    /// Mutates a session in place by ID, then refreshes derived state.
    /// Returns the updated record, or nil if not found.
    @discardableResult
    func mutateSession(id: SessionID, _ update: (inout SessionRecord) -> Void) -> SessionRecord? {
        guard let idx = sessionIndex[id] else { return nil }
        update(&sessions[idx])
        rebuildDerivedState()
        return sessions[idx]
    }

    /// Reorders the sessions array in place and rebuilds the index.
    func reorderSessionsInPlace(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
        for index in sessions.indices { sessions[index].orderIndex = index }
        rebuildSessionIndex()
    }

    /// Replaces all sessions and rebuilds the index. Use only for rollback in onFailure closures.
    func replaceAllSessions(_ newSessions: [SessionRecord]) {
        sessions = newSessions
        rebuildSessionIndex()
    }

    /// Single O(n) pass over `sessions` that refreshes all cached derived lists.
    /// Called by every mutation helper; Views consume the results rather than filtering inline.
    func rebuildDerivedState() {
        var active: [SessionRecord] = []
        var pinned: [SessionRecord] = []
        var activeTree: [SessionRecord] = []
        var ended: [SessionRecord] = []
        var titles: [SessionID: String] = [:]
        titles.reserveCapacity(sessions.count)
        for session in sessions {
            titles[session.id] = session.title
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
        sessionTitles = titles
    }
}
