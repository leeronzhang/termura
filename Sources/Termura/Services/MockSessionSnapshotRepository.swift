import Foundation

#if DEBUG

/// In-memory snapshot repository for unit tests and previews.
actor MockSessionSnapshotRepository: SessionSnapshotRepositoryProtocol {
    private var store: [SessionID: [String]] = [:]
    private(set) var saveCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var deleteCallCount = 0

    func save(lines: [String], for sessionID: SessionID) async throws {
        saveCallCount += 1
        let capped = Array(lines.suffix(AppConfig.Persistence.snapshotMaxLines))
        store[sessionID] = capped
    }

    func load(for sessionID: SessionID) async throws -> [String]? {
        loadCallCount += 1
        return store[sessionID]
    }

    func delete(for sessionID: SessionID) async throws {
        deleteCallCount += 1
        store[sessionID] = nil
    }
}

#endif
