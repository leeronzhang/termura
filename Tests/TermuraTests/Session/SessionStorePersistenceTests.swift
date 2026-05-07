@testable import Termura
import XCTest

@MainActor
final class SessionStorePersistenceTests: XCTestCase {
    private var engineFactory: MockTerminalEngineFactory!
    private var engineStore: TerminalEngineStore!
    private var repository: MockSessionRepository!
    private var store: SessionStore!
    private var clock: TestClock!

    override func setUp() async throws {
        engineFactory = MockTerminalEngineFactory()
        engineStore = TerminalEngineStore(factory: engineFactory)
        repository = MockSessionRepository()
        clock = TestClock()
        store = SessionStore(engineStore: engineStore, repository: repository, clock: clock)
    }

    override func tearDown() async throws {
        await engineStore.terminateAll()
    }

    func testCreateSessionCallsSave() async throws {
        let session = store.createSession(title: "Persist Me")
        await store.waitForPersistenceIdle()
        let saved = try await repository.fetchAll()
        XCTAssertTrue(saved.contains { $0.id == session.id })
    }

    func testDeleteSessionCallsDelete() async throws {
        let session = store.createSession(title: "To Close")
        await store.waitForPersistenceIdle()
        await store.deleteSession(id: session.id)
        let saved = try await repository.fetchAll()
        XCTAssertFalse(saved.contains { $0.id == session.id })
    }

    func testReorderSessionsCallsReorder() async throws {
        let first = store.createSession(title: "First")
        let second = store.createSession(title: "Second")
        await store.waitForPersistenceIdle()

        store.reorderSessions(from: IndexSet(integer: 0), to: 2)
        await store.waitForPersistenceIdle()

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
        await store.waitForPersistenceIdle()

        store.pinSession(id: session.id)
        await store.waitForPersistenceIdle()

        let saved = try await repository.fetchAll()
        XCTAssertEqual(saved.first(where: { $0.id == session.id })?.isPinned, true)
    }

    func testLoadPersistedSessionsRestoresSessions() async throws {
        let record = SessionRecord(title: "Restored Session")
        try await repository.save(record)

        await store.loadPersistedSessions()

        XCTAssertTrue(store.sessions.contains { $0.id == record.id })
    }

    func testLoadPersistedSessionsRestoresEngineInSessionWorkingDirectory() async throws {
        let record = SessionRecord(
            title: "Restored Session",
            workingDirectory: "/tmp/restored/subdir"
        )
        try await repository.save(record)

        await store.loadPersistedSessions()

        XCTAssertEqual(
            engineFactory.createdEngines.last?.currentDirectory,
            "/tmp/restored/subdir"
        )
    }

    func testEnsureEngineUsesPersistedWorkingDirectory() async throws {
        let older = SessionRecord(
            title: "Older",
            workingDirectory: "/tmp/older",
            lastActiveAt: Date(timeIntervalSince1970: 10)
        )
        let newer = SessionRecord(
            title: "Newer",
            workingDirectory: "/tmp/newer",
            lastActiveAt: Date(timeIntervalSince1970: 20)
        )
        try await repository.save(older)
        try await repository.save(newer)

        await store.loadPersistedSessions()
        store.activateSession(id: older.id)
        await store.waitForEngineActivationIdle()

        XCTAssertEqual(
            engineFactory.createdEngines.last?.currentDirectory,
            "/tmp/older"
        )
    }

    func testSetColorLabelPersists() async throws {
        let session = store.createSession(title: "Color Test")
        await store.waitForPersistenceIdle()

        store.setColorLabel(id: session.id, label: .green)
        await store.waitForPersistenceIdle()

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
