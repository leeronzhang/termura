import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionStore")

@MainActor
final class SessionStore: ObservableObject, SessionStoreProtocol {
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var activeSessionID: SessionID?

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
        guard let repo = repository else { return }
        do {
            let loaded = try await repo.fetchAll()
            sessions = loaded
            activeSessionID = loaded.first?.id
            for session in loaded {
                engineStore.createEngine(for: session.id, shell: defaultShell)
            }
            logger.info("Loaded \(loaded.count) persisted sessions")
        } catch {
            logger.error("Failed to load sessions: \(error)")
        }
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
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
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
        for index in sessions.indices { sessions[index].orderIndex = index }
        let ids = sessions.map(\.id)
        persistAsync { try await $0.reorder(ids: ids) }
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
