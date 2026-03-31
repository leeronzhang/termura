import Foundation

// MARK: - Session metadata mutations with optimistic-update + rollback
// Low-level index/array helpers (rebuildSessionIndex, appendSession, mutateSession,
// reorderSessionsInPlace, replaceAllSessions) live in SessionStore.swift because they
// write to private(set) properties — Swift restricts setters to the declaring file.

extension SessionStore {

    func renameSession(id: SessionID, title: String) {
        guard let updated = mutateSession(id: id, { $0.title = TitleSanitizer.stripAgentPrefixes(title) }) else { return }
        scheduleDebounced(key: "rename-\(id)") { try await $0.save(updated) }
    }

    func updateWorkingDirectory(id: SessionID, path: String) {
        guard let updated = mutateSession(id: id, {
            $0.workingDirectory = path
            $0.lastActiveAt = clock.now()
        }) else { return }
        scheduleDebounced(key: "workdir-\(id)") { try await $0.save(updated) }
    }

    func pinSession(id: SessionID) {
        guard let idx = sessionIndex[id] else { return }
        let oldValue = sessions[idx].isPinned
        // save() persists the full record including isPinned — no separate setPinned needed.
        guard let updated = mutateSession(id: id, { $0.isPinned = true }) else { return }
        persistTracked(
            { try await $0.save(updated) },
            onFailure: { [weak self] in self?.mutateSession(id: id) { $0.isPinned = oldValue } }
        )
    }

    func unpinSession(id: SessionID) {
        guard let idx = sessionIndex[id] else { return }
        let oldValue = sessions[idx].isPinned
        guard let updated = mutateSession(id: id, { $0.isPinned = false }) else { return }
        persistTracked(
            { try await $0.save(updated) },
            onFailure: { [weak self] in self?.mutateSession(id: id) { $0.isPinned = oldValue } }
        )
    }

    func setAgentType(id: SessionID, type: AgentType) {
        guard let idx = sessionIndex[id], sessions[idx].agentType != type else { return }
        let oldType = sessions[idx].agentType
        guard let updated = mutateSession(id: id, { $0.agentType = type }) else { return }
        persistTracked(
            { try await $0.save(updated) },
            onFailure: { [weak self] in self?.mutateSession(id: id) { $0.agentType = oldType } }
        )
    }

    func setColorLabel(id: SessionID, label: SessionColorLabel) {
        guard let idx = sessionIndex[id] else { return }
        let oldLabel = sessions[idx].colorLabel
        mutateSession(id: id) { $0.colorLabel = label }
        persistTracked(
            { try await $0.setColorLabel(id: id, label: label) },
            onFailure: { [weak self] in self?.mutateSession(id: id) { $0.colorLabel = oldLabel } }
        )
    }

    func reorderSessions(from source: IndexSet, to destination: Int) {
        let originalSessions = sessions
        reorderSessionsInPlace(from: source, to: destination)
        let ids = sessions.map(\.id)
        persistTracked(
            { try await $0.reorder(ids: ids) },
            onFailure: { [weak self] in self?.replaceAllSessions(originalSessions) }
        )
    }

}
