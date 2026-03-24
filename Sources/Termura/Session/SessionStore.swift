import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionStore")

@MainActor
final class SessionStore: ObservableObject, SessionStoreProtocol {
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var activeSessionID: SessionID?
    /// Set to `true` once persisted sessions have been loaded (or skipped).
    @Published private(set) var hasLoadedPersistedSessions = false
    /// IDs of sessions that were loaded from persistence (restored on launch).
    private(set) var restoredSessionIDs: Set<SessionID> = []

    private let engineStore: TerminalEngineStore
    private let defaultShell: String
    private let repository: (any SessionRepositoryProtocol)?
    private var saveTask: Task<Void, Never>?

    init(
        engineStore: TerminalEngineStore,
        shell: String = "",
        repository: (any SessionRepositoryProtocol)? = nil
    ) {
        self.engineStore = engineStore
        defaultShell = shell
        self.repository = repository
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
            if let activeID = activeSessionID,
               let session = loaded.first(where: { $0.id == activeID }) {
                let dir = session.workingDirectory.isEmpty ? nil : session.workingDirectory
                engineStore.createEngine(for: activeID, shell: defaultShell, currentDirectory: dir)
            }
            logger.info("Loaded \(loaded.count) persisted sessions")
        } catch {
            logger.error("Failed to load sessions: \(error)")
        }
    }

    // MARK: - Restored sessions

    func isRestoredSession(id: SessionID) -> Bool {
        restoredSessionIDs.contains(id)
    }

    // MARK: - SessionStoreProtocol

    @discardableResult
    func createSession(title: String = "", shell: String = "") -> SessionRecord {
        let resolvedShell = shell.isEmpty ? defaultShell : shell
        let resolvedTitle = title.isEmpty ? Self.defaultSessionTitle() : title
        let record = SessionRecord(title: resolvedTitle, orderIndex: sessions.count)
        sessions.append(record)
        engineStore.createEngine(for: record.id, shell: resolvedShell)
        activeSessionID = record.id
        persistAsync { try await $0.save(record) }
        logger.info("Created session \(record.id) title=\(resolvedTitle)")
        return record
    }

    /// Derives a human-readable session title from the current working directory basename.
    private static func defaultSessionTitle() -> String {
        let cwd = FileManager.default.currentDirectoryPath
        let basename = URL(fileURLWithPath: cwd).lastPathComponent
        return basename.isEmpty ? "Terminal" : basename
    }

    func closeSession(id: SessionID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: idx)
        engineStore.terminateEngine(for: id)
        if activeSessionID == id { activeSessionID = sessions.last?.id }
        persistAsync { try await $0.delete(id: id) }
        logger.info("Closed session \(id)")
    }

    func activateSession(id: SessionID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        activeSessionID = id
        // Lazy engine creation for restored sessions that haven't been activated yet.
        if engineStore.engine(for: id) == nil {
            let dir = session.workingDirectory.isEmpty ? nil : session.workingDirectory
            engineStore.createEngine(for: id, shell: defaultShell, currentDirectory: dir)
        }
    }

    func renameSession(id: SessionID, title: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].title = title
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
        persistAsync {
            try await $0.setPinned(id: id, pinned: true)
            try await $0.save(updated)
        }
    }

    func unpinSession(id: SessionID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned = false
        let updated = sessions[idx]
        persistAsync {
            try await $0.setPinned(id: id, pinned: false)
            try await $0.save(updated)
        }
    }

    func setColorLabel(id: SessionID, label: SessionColorLabel) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].colorLabel = label
        persistAsync { try await $0.setColorLabel(id: id, label: label) }
    }

    func reorderSessions(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
        for index in sessions.indices {
            sessions[index].orderIndex = index
        }
        let ids = sessions.map(\.id)
        persistAsync { try await $0.reorder(ids: ids) }
    }

    // MARK: - Session Tree

    @discardableResult
    func createBranch(from sessionID: SessionID, type: BranchType, title: String = "") async -> SessionRecord? {
        guard let repo = repository else {
            logger.warning("Cannot create branch without repository")
            return nil
        }
        let resolvedTitle = title.isEmpty ? "\(type.rawValue.capitalized) branch" : title
        do {
            let branch = try await repo.createBranch(from: sessionID, type: type, title: resolvedTitle)
            sessions.append(branch)
            engineStore.createEngine(for: branch.id, shell: defaultShell)
            activeSessionID = branch.id
            logger.info("Created branch \(branch.id) from \(sessionID)")
            return branch
        } catch {
            logger.error("Failed to create branch: \(error)")
            return nil
        }
    }

    /// Merge a branch summary back to the parent session.
    func mergeBranchSummary(
        branchID: SessionID,
        summary: String,
        messageRepo: (any SessionMessageRepositoryProtocol)?
    ) async {
        guard let repo = repository,
              let idx = sessions.firstIndex(where: { $0.id == branchID }),
              let parentID = sessions[idx].parentID else { return }

        // Update the branch's summary field
        do {
            try await repo.updateSummary(branchID, summary: summary)
            sessions[idx].summary = summary

            // Insert summary as metadata message in parent session
            if let msgRepo = messageRepo {
                let summarizer = BranchSummarizer()
                let msg = await summarizer.createSummaryMessage(
                    summary: summary,
                    branchSessionID: branchID,
                    parentSessionID: parentID
                )
                try await msgRepo.save(msg)
            }

            // Navigate back to parent
            activeSessionID = parentID
            logger.info("Merged branch \(branchID) summary to parent \(parentID)")
        } catch {
            logger.error("Failed to merge branch summary: \(error)")
        }
    }

    func navigateToParent(of sessionID: SessionID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }),
              let parentID = sessions[idx].parentID,
              sessions.contains(where: { $0.id == parentID }) else {
            return
        }
        activeSessionID = parentID
    }

    // MARK: - Private persistence helpers

    private func persistAsync(
        _ operation: @Sendable @escaping (any SessionRepositoryProtocol) async throws -> Void
    ) {
        guard let repo = repository else { return }
        Task {
            do {
                try await operation(repo)
            } catch {
                logger.error("Persistence error: \(error)")
            }
        }
    }

    private func scheduleDebounced(
        _ operation: @Sendable @escaping (any SessionRepositoryProtocol) async throws -> Void
    ) {
        guard let repo = repository else { return }
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(for: .seconds(AppConfig.Runtime.notesAutoSaveSeconds))
                guard !Task.isCancelled else { return }
                try await operation(repo)
            } catch is CancellationError {
                return
            } catch {
                logger.error("Debounced save error: \(error)")
            }
        }
    }
}
