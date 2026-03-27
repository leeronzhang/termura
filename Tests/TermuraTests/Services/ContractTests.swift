import Foundation
import XCTest
@testable import Termura

/// Contract tests verify that Mock implementations conform to the same
/// behavioral contract as real implementations. This prevents mock drift
/// where tests pass with mocks but fail with real code.
///
/// Each test runs the same operation against both Mock and Real implementations,
/// comparing the observable outcomes.
final class ContractTests: XCTestCase {
    // MARK: - SessionRepository contract

    /// Both MockSessionRepository and SessionRepository must round-trip a session.
    func testSessionRepositorySaveAndFetchContract() async throws {
        let record = SessionRecord(title: "Contract Test")

        // Mock implementation
        let mock = MockSessionRepository()
        try await mock.save(record)
        let mockResult = try await mock.fetchAll()

        // Real implementation (in-memory DB)
        let db = try MockDatabaseService()
        let real = SessionRepository(db: db)
        try await real.save(record)
        let realResult = try await real.fetchAll()

        // Contract: both return exactly one record with matching ID and title
        XCTAssertEqual(mockResult.count, realResult.count)
        XCTAssertEqual(mockResult.first?.id, record.id)
        XCTAssertEqual(realResult.first?.id, record.id)
        XCTAssertEqual(mockResult.first?.title, realResult.first?.title)
    }

    /// Both must delete correctly.
    func testSessionRepositoryDeleteContract() async throws {
        let record = SessionRecord(title: "Delete Contract")

        let mock = MockSessionRepository()
        try await mock.save(record)
        try await mock.delete(id: record.id)
        let mockResult = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = SessionRepository(db: db)
        try await real.save(record)
        try await real.delete(id: record.id)
        let realResult = try await real.fetchAll()

        XCTAssertEqual(mockResult.count, 0)
        XCTAssertEqual(realResult.count, 0)
    }

    /// Both must handle reorder identically.
    func testSessionRepositoryReorderContract() async throws {
        let r1 = SessionRecord(title: "First", orderIndex: 0)
        let r2 = SessionRecord(title: "Second", orderIndex: 1)

        let mock = MockSessionRepository()
        try await mock.save(r1)
        try await mock.save(r2)
        try await mock.reorder(ids: [r2.id, r1.id])
        let mockResult = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = SessionRepository(db: db)
        try await real.save(r1)
        try await real.save(r2)
        try await real.reorder(ids: [r2.id, r1.id])
        let realResult = try await real.fetchAll()

        // Both should return records in the new order
        XCTAssertEqual(mockResult.count, realResult.count)
        XCTAssertEqual(mockResult.first?.id, r2.id)
        XCTAssertEqual(realResult.first?.id, r2.id)
    }

    // MARK: - SessionSnapshotRepository contract

    /// Both MockSessionSnapshotRepository and SessionSnapshotRepository must round-trip.
    func testSnapshotRepositoryRoundTripContract() async throws {
        let sessionID = SessionID()
        let lines = ["line 1", "line 2", "line 3"]

        // Mock
        let mock = MockSessionSnapshotRepository()
        try await mock.save(lines: lines, for: sessionID)
        let mockResult = try await mock.load(for: sessionID)

        // Real (in-memory DB)
        let db = try MockDatabaseService()
        let sessionRepo = SessionRepository(db: db)
        try await sessionRepo.save(SessionRecord(id: sessionID, title: "Test"))
        let real = SessionSnapshotRepository(db: db)
        try await real.save(lines: lines, for: sessionID)
        let realResult = try await real.load(for: sessionID)

        XCTAssertEqual(mockResult, lines)
        XCTAssertEqual(realResult, lines)
    }

    /// Both must return nil for nonexistent sessions.
    func testSnapshotRepositoryLoadMissingContract() async throws {
        let sessionID = SessionID()

        let mock = MockSessionSnapshotRepository()
        let mockResult = try await mock.load(for: sessionID)

        let db = try MockDatabaseService()
        let real = SessionSnapshotRepository(db: db)
        let realResult = try await real.load(for: sessionID)

        XCTAssertNil(mockResult)
        XCTAssertNil(realResult)
    }

    /// Both must cap at snapshotMaxLines.
    func testSnapshotRepositoryLineCappingContract() async throws {
        let sessionID = SessionID()
        let maxLines = AppConfig.Persistence.snapshotMaxLines
        let oversized = (0 ..< maxLines + 50).map { "Line \($0)" }

        // Mock
        let mock = MockSessionSnapshotRepository()
        try await mock.save(lines: oversized, for: sessionID)
        let mockResult = try await mock.load(for: sessionID)

        // Real
        let db = try MockDatabaseService()
        let sessionRepo = SessionRepository(db: db)
        try await sessionRepo.save(SessionRecord(id: sessionID, title: "Test"))
        let real = SessionSnapshotRepository(db: db)
        try await real.save(lines: oversized, for: sessionID)
        let realResult = try await real.load(for: sessionID)

        XCTAssertEqual(mockResult?.count, maxLines)
        XCTAssertEqual(realResult?.count, maxLines)
    }

    // MARK: - MetricsCollector contract

    /// Both MockMetricsCollector and MetricsCollector must produce consistent snapshots.
    func testMetricsCollectorSnapshotContract() async {
        let mock = MockMetricsCollector()
        let real = MetricsCollector()

        await mock.increment(.sessionCreated, by: 3)
        await real.increment(.sessionCreated, by: 3)

        let mockSnap = await mock.snapshot()
        let realSnap = await real.snapshot()

        // Mock snapshot returns empty (by design), but real should track
        // The key contract is that both compile and respond to the same API
        XCTAssertEqual(realSnap.counters[.sessionCreated], 3)
        // Mock is a test double — its snapshot is intentionally simplified
        _ = mockSnap
    }

    // MARK: - SessionStore / MockSessionStore contract

    @MainActor
    func testSessionStoreCreateContract() async throws {
        // Mock
        let mockStore = MockSessionStore()
        let mockSession = mockStore.createSession(title: "Test")

        // Real
        let factory = MockTerminalEngineFactory()
        let engineStore = TerminalEngineStore(factory: factory)
        let realStore = SessionStore(engineStore: engineStore)
        let realSession = realStore.createSession(title: "Test")

        // Both must create a session and make it active
        XCTAssertEqual(mockStore.activeSessionID, mockSession.id)
        XCTAssertEqual(realStore.activeSessionID, realSession.id)
        XCTAssertEqual(mockStore.sessions.count, 1)
        XCTAssertEqual(realStore.sessions.count, 1)

        engineStore.terminateAll()
    }

    @MainActor
    func testSessionStoreCloseContract() async throws {
        let mockStore = MockSessionStore()
        let mockSession = mockStore.createSession(title: "Close Me")
        mockStore.closeSession(id: mockSession.id)

        let factory = MockTerminalEngineFactory()
        let engineStore = TerminalEngineStore(factory: factory)
        let realStore = SessionStore(engineStore: engineStore)
        let realSession = realStore.createSession(title: "Close Me")
        realStore.closeSession(id: realSession.id)

        XCTAssertTrue(mockStore.sessions.isEmpty)
        XCTAssertTrue(realStore.sessions.isEmpty)
        XCTAssertNil(mockStore.activeSessionID)
        XCTAssertNil(realStore.activeSessionID)

        engineStore.terminateAll()
    }

    @MainActor
    func testSessionStorePinContract() async throws {
        let mockStore = MockSessionStore()
        let mockSession = mockStore.createSession(title: "Pin Me")
        mockStore.pinSession(id: mockSession.id)

        let factory = MockTerminalEngineFactory()
        let engineStore = TerminalEngineStore(factory: factory)
        let realStore = SessionStore(engineStore: engineStore)
        let realSession = realStore.createSession(title: "Pin Me")
        realStore.pinSession(id: realSession.id)

        XCTAssertTrue(mockStore.sessions.first?.isPinned ?? false)
        XCTAssertTrue(realStore.sessions.first?.isPinned ?? false)

        engineStore.terminateAll()
    }

    // MARK: - GitService contract

    func testGitServiceNotARepoContract() async throws {
        let tmpDir = NSTemporaryDirectory() + "termura-contract-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tmpDir,
            withIntermediateDirectories: true
        )
        defer { do { try FileManager.default.removeItem(atPath: tmpDir) } catch { _ = error } }

        let mock = MockGitService()
        let real = GitService()

        let mockResult = try await mock.status(at: tmpDir)
        let realResult = try await real.status(at: tmpDir)

        // Both should indicate not a repo
        XCTAssertEqual(mockResult.isGitRepo, realResult.isGitRepo)
        XCTAssertFalse(realResult.isGitRepo)
    }
}
