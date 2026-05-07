import Foundation
@testable import Termura
import XCTest

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

    /// Round-trip: counter increments must accumulate identically in both implementations.
    func testMetricsCollectorCounterRoundTrip() async {
        let mock = MockMetricsCollector()
        let real = MetricsCollector()

        await mock.increment(.sessionCreated, by: 1)
        await mock.increment(.sessionCreated, by: 2)
        await real.increment(.sessionCreated, by: 1)
        await real.increment(.sessionCreated, by: 2)

        let mockSnap = await mock.snapshot()
        let realSnap = await real.snapshot()

        // Both must accumulate: 1 + 2 = 3
        XCTAssertEqual(mockSnap.counters[.sessionCreated], 3)
        XCTAssertEqual(realSnap.counters[.sessionCreated], 3)
        XCTAssertEqual(mockSnap.counters[.sessionCreated], realSnap.counters[.sessionCreated])
    }

    /// Round-trip: gauge writes must follow last-write-wins semantics in both implementations.
    func testMetricsCollectorGaugeRoundTrip() async {
        let mock = MockMetricsCollector()
        let real = MetricsCollector()

        await mock.gauge(.activeSessions, value: 5)
        await mock.gauge(.activeSessions, value: 7)
        await real.gauge(.activeSessions, value: 5)
        await real.gauge(.activeSessions, value: 7)

        let mockSnap = await mock.snapshot()
        let realSnap = await real.snapshot()

        // Both must reflect the last written value (last-write-wins).
        XCTAssertEqual(mockSnap.gauges[.activeSessions], 7)
        XCTAssertEqual(realSnap.gauges[.activeSessions], 7)
        XCTAssertEqual(mockSnap.gauges[.activeSessions], realSnap.gauges[.activeSessions])
    }

    /// Round-trip: histogram counts must equal the number of recordDuration calls in both.
    func testMetricsCollectorHistogramRoundTrip() async {
        let mock = MockMetricsCollector()
        let real = MetricsCollector()

        await mock.recordDuration(.dbWriteDuration, seconds: 0.1)
        await mock.recordDuration(.dbWriteDuration, seconds: 0.2)
        await real.recordDuration(.dbWriteDuration, seconds: 0.1)
        await real.recordDuration(.dbWriteDuration, seconds: 0.2)

        let mockSnap = await mock.snapshot()
        let realSnap = await real.snapshot()

        // Both must count exactly 2 recordings.
        XCTAssertEqual(mockSnap.histogramCounts[.dbWriteDuration], 2)
        XCTAssertEqual(realSnap.histogramCounts[.dbWriteDuration], 2)
        XCTAssertEqual(
            mockSnap.histogramCounts[.dbWriteDuration],
            realSnap.histogramCounts[.dbWriteDuration]
        )
    }

    /// Missing / never-recorded: both must return nil for metrics that were never written.
    func testMetricsCollectorMissingMetricReturnsNil() async {
        let mock = MockMetricsCollector()
        let real = MetricsCollector()

        let mockSnap = await mock.snapshot()
        let realSnap = await real.snapshot()

        XCTAssertNil(mockSnap.counters[.sessionClosed])
        XCTAssertNil(realSnap.counters[.sessionClosed])
        XCTAssertNil(mockSnap.gauges[.activeAgents])
        XCTAssertNil(realSnap.gauges[.activeAgents])
        XCTAssertNil(mockSnap.histogramCounts[.searchDuration])
        XCTAssertNil(realSnap.histogramCounts[.searchDuration])
    }

    /// Boundary: default increment (by: 1) must register as 1 in both implementations.
    func testMetricsCollectorDefaultIncrementBoundary() async {
        let mock = MockMetricsCollector()
        let real = MetricsCollector()

        await mock.increment(.dbWrite)
        await real.increment(.dbWrite)

        let mockSnap = await mock.snapshot()
        let realSnap = await real.snapshot()

        XCTAssertEqual(mockSnap.counters[.dbWrite], 1)
        XCTAssertEqual(realSnap.counters[.dbWrite], 1)
        XCTAssertEqual(mockSnap.counters[.dbWrite], realSnap.counters[.dbWrite])
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
        let realStore = SessionStore(engineStore: engineStore, repository: MockSessionRepository())
        let realSession = realStore.createSession(title: "Test")

        // Both must create a session and make it active
        XCTAssertEqual(mockStore.activeSessionID, mockSession.id)
        XCTAssertEqual(realStore.activeSessionID, realSession.id)
        XCTAssertEqual(mockStore.sessions.count, 1)
        XCTAssertEqual(realStore.sessions.count, 1)

        await engineStore.terminateAll()
    }

    @MainActor
    func testSessionStoreDeleteContract() async throws {
        let mockStore = MockSessionStore()
        let mockSession = mockStore.createSession(title: "Close Me")
        await mockStore.deleteSession(id: mockSession.id)

        let factory = MockTerminalEngineFactory()
        let engineStore = TerminalEngineStore(factory: factory)
        let realStore = SessionStore(engineStore: engineStore, repository: MockSessionRepository())
        let realSession = realStore.createSession(title: "Close Me")
        await realStore.deleteSession(id: realSession.id)

        XCTAssertTrue(mockStore.sessions.isEmpty)
        XCTAssertTrue(realStore.sessions.isEmpty)
        XCTAssertNil(mockStore.activeSessionID)
        XCTAssertNil(realStore.activeSessionID)

        await engineStore.terminateAll()
    }

    @MainActor
    func testSessionStorePinContract() async throws {
        let mockStore = MockSessionStore()
        let mockSession = mockStore.createSession(title: "Pin Me")
        mockStore.pinSession(id: mockSession.id)

        let factory = MockTerminalEngineFactory()
        let engineStore = TerminalEngineStore(factory: factory)
        let realStore = SessionStore(engineStore: engineStore, repository: MockSessionRepository())
        let realSession = realStore.createSession(title: "Pin Me")
        realStore.pinSession(id: realSession.id)

        XCTAssertTrue(mockStore.sessions.first?.isPinned ?? false)
        XCTAssertTrue(realStore.sessions.first?.isPinned ?? false)

        await engineStore.terminateAll()
    }

    // MARK: - SessionRepository extended contract

    /// Both must truncate summary at summaryMaxLength.
    func testUpdateSummaryTruncationContract() async throws {
        let record = SessionRecord(title: "Summary Truncation Contract")
        let oversized = String(repeating: "x", count: AppConfig.SessionTree.summaryMaxLength + 50)

        let mock = MockSessionRepository()
        try await mock.save(record)
        try await mock.updateSummary(record.id, summary: oversized)
        let mockResult = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = SessionRepository(db: db)
        try await real.save(record)
        try await real.updateSummary(record.id, summary: oversized)
        let realResult = try await real.fetchAll()

        XCTAssertEqual(mockResult.first?.summary?.count, AppConfig.SessionTree.summaryMaxLength)
        XCTAssertEqual(realResult.first?.summary?.count, AppConfig.SessionTree.summaryMaxLength)
        XCTAssertEqual(mockResult.first?.summary, realResult.first?.summary)
    }

    /// Both must set endedAt on markEnded and clear it on markReopened.
    func testMarkEndedMarkReopenedContract() async throws {
        let record = SessionRecord(title: "Lifecycle Contract")
        let stamp = Date()

        let mock = MockSessionRepository()
        try await mock.save(record)
        try await mock.markEnded(id: record.id, at: stamp)
        let mockEnded = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = SessionRepository(db: db)
        try await real.save(record)
        try await real.markEnded(id: record.id, at: stamp)
        let realEnded = try await real.fetchAll()

        // Both must have endedAt set.
        XCTAssertNotNil(mockEnded.first?.endedAt)
        XCTAssertNotNil(realEnded.first?.endedAt)

        try await mock.markReopened(id: record.id)
        try await real.markReopened(id: record.id)

        let mockReopened = try await mock.fetchAll()
        let realReopened = try await real.fetchAll()

        // Both must have endedAt cleared.
        XCTAssertNil(mockReopened.first?.endedAt)
        XCTAssertNil(realReopened.first?.endedAt)
    }

    /// Both must persist a new color label.
    func testSetColorLabelContract() async throws {
        let record = SessionRecord(title: "Color Label Contract", colorLabel: .none)

        let mock = MockSessionRepository()
        try await mock.save(record)
        try await mock.setColorLabel(id: record.id, label: .purple)
        let mockResult = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = SessionRepository(db: db)
        try await real.save(record)
        try await real.setColorLabel(id: record.id, label: .purple)
        let realResult = try await real.fetchAll()

        XCTAssertEqual(mockResult.first?.colorLabel, .purple)
        XCTAssertEqual(realResult.first?.colorLabel, .purple)
        XCTAssertEqual(mockResult.first?.colorLabel, realResult.first?.colorLabel)
    }

    /// Both must toggle isPinned in both directions.
    func testSetPinnedContract() async throws {
        let record = SessionRecord(title: "Pin Contract", isPinned: false)

        let mock = MockSessionRepository()
        try await mock.save(record)
        try await mock.setPinned(id: record.id, pinned: true)
        let mockPinned = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = SessionRepository(db: db)
        try await real.save(record)
        try await real.setPinned(id: record.id, pinned: true)
        let realPinned = try await real.fetchAll()

        XCTAssertEqual(mockPinned.first?.isPinned, true)
        XCTAssertEqual(realPinned.first?.isPinned, true)

        try await mock.setPinned(id: record.id, pinned: false)
        try await real.setPinned(id: record.id, pinned: false)

        let mockUnpinned = try await mock.fetchAll()
        let realUnpinned = try await real.fetchAll()

        XCTAssertEqual(mockUnpinned.first?.isPinned, false)
        XCTAssertEqual(realUnpinned.first?.isPinned, false)
        XCTAssertEqual(mockUnpinned.first?.isPinned, realUnpinned.first?.isPinned)
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
