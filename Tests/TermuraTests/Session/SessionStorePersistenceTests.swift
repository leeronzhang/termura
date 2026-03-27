import XCTest
@testable import Termura

@MainActor
final class SessionStorePersistenceTests: XCTestCase {
    private var engineFactory: MockTerminalEngineFactory!
    private var engineStore: TerminalEngineStore!
    private var repository: MockSessionRepository!
    private var store: SessionStore!

    override func setUp() async throws {
        engineFactory = MockTerminalEngineFactory()
        engineStore = TerminalEngineStore(factory: engineFactory)
        repository = MockSessionRepository()
        store = SessionStore(engineStore: engineStore, repository: repository)
    }

    override func tearDown() async throws {
        engineStore.terminateAll()
    }

    func testCreateSessionCallsSave() async throws {
        let session = store.createSession(title: "Persist Me")
        // Allow the fire-and-forget Task to complete
        try await yieldForDuration(seconds: 0.05)
        let saved = try await repository.fetchAll()
        XCTAssertTrue(saved.contains { $0.id == session.id })
    }

    func testCloseSessionCallsDelete() async throws {
        let session = store.createSession(title: "To Close")
        try await yieldForDuration(seconds: 0.05)
        store.closeSession(id: session.id)
        try await yieldForDuration(seconds: 0.05)
        let saved = try await repository.fetchAll()
        XCTAssertFalse(saved.contains { $0.id == session.id })
    }

    func testReorderSessionsCallsReorder() async throws {
        let first = store.createSession(title: "First")
        let second = store.createSession(title: "Second")
        try await yieldForDuration(seconds: 0.05)

        store.reorderSessions(from: IndexSet(integer: 0), to: 2)
        try await yieldForDuration(seconds: 0.05)

        let saved = try await repository.fetchAll()
        // After moving first to end, second should come before first
        let titles = saved.map(\.title)
        if titles.count == 2 {
            XCTAssertEqual(titles.first, "Second")
        }
        _ = first
        _ = second
    }

    func testPinSessionCallsSetPinnedAndSave() async throws {
        let session = store.createSession(title: "Pin Test")
        try await yieldForDuration(seconds: 0.05)

        store.pinSession(id: session.id)
        try await yieldForDuration(seconds: 0.05)

        let saved = try await repository.fetchAll()
        XCTAssertEqual(saved.first(where: { $0.id == session.id })?.isPinned, true)
    }

    func testLoadPersistedSessionsRestoresSessions() async throws {
        let record = SessionRecord(title: "Restored Session")
        try await repository.save(record)

        await store.loadPersistedSessions()

        XCTAssertTrue(store.sessions.contains { $0.id == record.id })
    }

    func testSetColorLabelPersists() async throws {
        let session = store.createSession(title: "Color Test")
        try await yieldForDuration(seconds: 0.05)

        store.setColorLabel(id: session.id, label: .green)
        try await yieldForDuration(seconds: 0.05)

        let saved = try await repository.fetchAll()
        XCTAssertEqual(saved.first(where: { $0.id == session.id })?.colorLabel, .green)
    }

    // MARK: - Flush tests

    func testFlushAwaitsTrackedWrites() async throws {
        let session = store.createSession(title: "Flush Test")
        // Do NOT yield — call flush immediately to prove it awaits pending writes.
        await store.flushPendingWrites()

        let saved = try await repository.fetchAll()
        XCTAssertTrue(saved.contains { $0.id == session.id })
    }

    func testFlushPersistsDebouncedRename() async throws {
        let session = store.createSession(title: "Original")
        await store.flushPendingWrites()

        store.renameSession(id: session.id, title: "Renamed")
        // Rename uses debounce — without flush, DB would still have "Original".
        await store.flushPendingWrites()

        let saved = try await repository.fetchAll()
        XCTAssertEqual(saved.first(where: { $0.id == session.id })?.title, "Renamed")
    }

    func testFlushPersistsDebouncedWorkingDirectory() async throws {
        let session = store.createSession(title: "Dir Test")
        await store.flushPendingWrites()

        store.updateWorkingDirectory(id: session.id, path: "/new/path")
        await store.flushPendingWrites()

        let saved = try await repository.fetchAll()
        XCTAssertEqual(
            saved.first(where: { $0.id == session.id })?.workingDirectory,
            "/new/path"
        )
    }
}
