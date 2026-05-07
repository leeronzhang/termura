@testable import Termura
import XCTest

/// Tests for SessionStore persistence error recovery, flush semantics,
/// and debounced write behavior.
@MainActor
final class SessionStorePersistenceErrorTests: XCTestCase {
    private var engineStore = TerminalEngineStore(factory: MockTerminalEngineFactory())
    private var repository = MockSessionRepository()
    private var clock = TestClock()
    private var metricsCollector = MockMetricsCollector()

    override func setUp() async throws {
        engineStore = TerminalEngineStore(factory: MockTerminalEngineFactory())
        repository = MockSessionRepository()
        clock = TestClock()
        metricsCollector = MockMetricsCollector()
    }

    override func tearDown() async throws {
        await engineStore.terminateAll()
    }

    private func makeStore(
        repository: MockSessionRepository? = nil,
        projectRoot: String? = nil
    ) -> SessionStore {
        SessionStore(
            engineStore: engineStore,
            projectRoot: projectRoot,
            repository: repository ?? self.repository,
            clock: clock,
            metricsCollector: metricsCollector
        )
    }

    // MARK: - persistTracked error recovery

    func testPersistTrackedLogsErrorButDoesNotCrash() async throws {
        let store = makeStore()
        store.createSession(title: "Test")
        store.persistTracked { _ in
            throw RepositoryError.compressionFailed
        }
        await store.waitForPersistenceIdle()
    }

    func testPersistTrackedWritesToRepository() async throws {
        let store = makeStore()
        store.createSession(title: "Test")
        await store.flushPendingWrites()
        let saved = try await repository.fetchAll()
        XCTAssertFalse(saved.isEmpty, "persistTracked should have saved the session to the repository")
    }

    // MARK: - scheduleDebounced cancellation

    func testScheduleDebouncedCancelsOnReentry() async throws {
        let store = makeStore()
        store.createSession(title: "Initial")
        await store.flushPendingWrites()

        store.renameSession(id: store.sessions[0].id, title: "First")
        store.renameSession(id: store.sessions[0].id, title: "Second")

        await store.flushPendingWrites()

        let saved = try await repository.fetchAll()
        XCTAssertEqual(saved.first?.title, "Second")
    }

    func testScheduleDebouncedUsesClockSleep() async throws {
        let store = makeStore()
        store.createSession(title: "Clock Test")
        await store.flushPendingWrites()

        store.renameSession(id: store.sessions[0].id, title: "Renamed")
        await store.waitForPersistenceIdle()

        XCTAssertGreaterThan(clock.sleepCallCount, 0)
    }

    // MARK: - flushPendingWrites

    func testFlushWithEmptyStoreIsNoOp() async throws {
        let store = SessionStore(engineStore: engineStore, repository: MockSessionRepository())
        await store.flushPendingWrites()
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testFlushCancelsDebouncedTaskAndSaves() async throws {
        let store = makeStore()
        store.createSession(title: "Flush Cancel")
        await store.flushPendingWrites()

        store.renameSession(id: store.sessions[0].id, title: "Debounced")
        await store.flushPendingWrites()

        // After flush, the debounced rename must have been force-saved.
        let saved = try await repository.fetchAll()
        XCTAssertEqual(saved.first?.title, "Debounced", "flush must save debounced renames")
    }

    func testFlushForcesSaveForAllSessions() async throws {
        let store = makeStore()
        let s1 = store.createSession(title: "Session A")
        let s2 = store.createSession(title: "Session B")

        await store.flushPendingWrites()

        let saved = try await repository.fetchAll()
        let ids = saved.map(\.id)
        XCTAssertTrue(ids.contains(s1.id))
        XCTAssertTrue(ids.contains(s2.id))
    }

    // MARK: - loadPersistedSessions error recovery

    func testLoadPersistedSessionsWithEmptyRepositorySetsLoadedFlag() async throws {
        let store = SessionStore(engineStore: engineStore, repository: MockSessionRepository())
        await store.loadPersistedSessions()

        XCTAssertTrue(store.hasLoadedPersistedSessions)
        XCTAssertNil(store.errorMessage)
    }

    func testLoadPersistedSessionsActivatesMostRecent() async throws {
        let store = makeStore()
        let old = SessionRecord(
            title: "Old",
            lastActiveAt: Date().addingTimeInterval(-3600)
        )
        let recent = SessionRecord(
            title: "Recent",
            lastActiveAt: Date()
        )
        try await repository.save(old)
        try await repository.save(recent)

        await store.loadPersistedSessions()

        XCTAssertEqual(store.activeSessionID, recent.id)
        XCTAssertTrue(store.hasLoadedPersistedSessions)
    }

    func testLoadPersistedSessionsMarksRestoredIDs() async throws {
        let store = makeStore()
        let record = SessionRecord(title: "Restored")
        try await repository.save(record)

        await store.loadPersistedSessions()

        XCTAssertTrue(store.isRestoredSession(id: record.id))
    }

    // MARK: - createBranch error recovery

    func testCreateBranchSetsActiveSesssion() async throws {
        let store = makeStore()
        let root = store.createSession(title: "Root")
        await store.flushPendingWrites()
        await store.createBranch(from: root.id, type: .investigation, title: "My Branch")
        let branch = store.sessions.first { $0.id == store.activeSessionID }
        XCTAssertNotNil(branch)
        XCTAssertEqual(store.activeSessionID, branch?.id)
        XCTAssertEqual(branch?.parentID, root.id)
    }

    func testCreateBranchSuccessActivatesBranch() async throws {
        let store = makeStore()
        let root = store.createSession(title: "Root")
        await store.flushPendingWrites()

        await store.createBranch(from: root.id, type: .investigation, title: "Debug branch")
        let branch = store.sessions.first { $0.id == store.activeSessionID }

        XCTAssertNotNil(branch)
        XCTAssertEqual(store.activeSessionID, branch?.id)
        XCTAssertNil(store.errorMessage)
    }

    // MARK: - Metrics integration

    func testCreateSessionRecordsMetrics() async throws {
        let store = makeStore()
        store.createSession(title: "Metric Test")
        try await waitUntil { [self] in
            await metricsCollector.incrementCount(for: .sessionCreated) == 1
        }

        let count = await metricsCollector.incrementCount(for: .sessionCreated)
        XCTAssertEqual(count, 1)
    }

    func testDeleteSessionRecordsMetrics() async throws {
        let store = makeStore()
        let session = store.createSession(title: "Close Metric")
        await store.waitForPersistenceIdle()

        await store.deleteSession(id: session.id)
        try await waitUntil { [self] in
            await metricsCollector.incrementCount(for: .sessionClosed) == 1
        }

        let count = await metricsCollector.incrementCount(for: .sessionClosed)
        XCTAssertEqual(count, 1)
    }

    func testActivateSessionRecordsDuration() async throws {
        let store = makeStore()
        let session = store.createSession(title: "Duration Test")
        await store.waitForPersistenceIdle()

        store.activateSession(id: session.id)
        try await waitUntil { [self] in
            await metricsCollector.hasDuration(for: .sessionSwitchDuration)
        }

        let hasDuration = await metricsCollector.hasDuration(for: .sessionSwitchDuration)
        XCTAssertTrue(hasDuration)
    }
}
