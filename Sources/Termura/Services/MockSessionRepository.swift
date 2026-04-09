import Foundation

#if DEBUG

/// In-memory session repository for debug previews. No GRDB dependency.
actor DebugSessionRepository: SessionRepositoryProtocol {
    private var store: [SessionID: SessionRecord] = [:]
    private var order: [SessionID] = []

    func fetchAll() async throws -> [SessionRecord] {
        order.compactMap { store[$0] }
    }

    func fetch(id: SessionID) async throws -> SessionRecord? {
        store[id]
    }

    func save(_ record: SessionRecord) async throws {
        if store[record.id] == nil { order.append(record.id) }
        store[record.id] = record
    }

    func delete(id: SessionID) async throws {
        store[id] = nil
        order.removeAll { $0 == id }
    }

    func archive(id: SessionID) async throws {
        store[id] = nil
        order.removeAll { $0 == id }
    }

    func search(query: String) async throws -> [SessionRecord] {
        let lowered = query.lowercased()
        return order.compactMap { store[$0] }.filter {
            $0.title.lowercased().contains(lowered) ||
                ($0.workingDirectory ?? "").lowercased().contains(lowered)
        }
    }

    func reorder(ids: [SessionID]) async throws {
        let filtered = ids.filter { store[$0] != nil }
        order = filtered
        for (index, id) in filtered.enumerated() {
            store[id]?.orderIndex = index
        }
    }

    func setColorLabel(id: SessionID, label: SessionColorLabel) async throws {
        store[id]?.colorLabel = label
    }

    func setPinned(id: SessionID, pinned: Bool) async throws {
        store[id]?.isPinned = pinned
    }

    // MARK: - Session Tree

    func fetchChildren(of parentID: SessionID) async throws -> [SessionRecord] {
        order.compactMap { store[$0] }.filter { $0.parentID == parentID }
    }

    func fetchAncestors(of sessionID: SessionID) async throws -> [SessionRecord] {
        var ancestors: [SessionRecord] = []
        var currentID = store[sessionID]?.parentID
        while let parentID = currentID, let parent = store[parentID] {
            ancestors.append(parent)
            currentID = parent.parentID
        }
        return ancestors
    }

    func createBranch(from parentID: SessionID, type: BranchType, title: String) async throws -> SessionRecord {
        let parent = store[parentID]
        let record = SessionRecord(
            title: title,
            workingDirectory: parent?.workingDirectory,
            parentID: parentID,
            branchType: type
        )
        store[record.id] = record
        order.append(record.id)
        return record
    }

    func updateSummary(_ sessionID: SessionID, summary: String) async throws {
        store[sessionID]?.summary = String(summary.prefix(AppConfig.SessionTree.summaryMaxLength))
    }

    func markEnded(id: SessionID, at date: Date) async throws {
        store[id]?.status = .ended(at: date)
    }

    func markReopened(id: SessionID) async throws {
        store[id]?.status = .active
    }
}

#endif
