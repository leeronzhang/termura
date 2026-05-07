import Foundation
@testable import Termura
import XCTest

/// Contract tests verifying that in-memory mock repositories preserve the behavioral
/// contracts of their GRDB-backed real implementations.
///
/// Covered protocols:
///   - HarnessEventRepositoryProtocol (MockHarnessEventRepository vs HarnessEventRepository)
///   - SessionMessageRepositoryProtocol (MockSessionMessageRepository vs SessionMessageRepository)
///
/// Known divergence — SessionMessageRepository.countTokens:
///   Real:  sums token_count column across matching rows
///   Mock:  always returns 0 (stub — intentionally simplified)
/// This drift is documented here but countTokens accuracy is tested in
/// SessionMessageRepositoryTests.swift (real-only).
final class HarnessAndMessageRepositoryContractTests: XCTestCase {
    // MARK: - HarnessEventRepository: round-trip

    /// Both implementations must return the saved event on fetchEvents.
    func testHarnessEventRepositorySaveAndFetchContract() async throws {
        let sessionID = SessionID()
        let event = HarnessEvent(
            sessionID: sessionID,
            eventType: .ruleAppend,
            payload: "{\"key\":\"value\"}"
        )

        // Mock
        let mock = MockHarnessEventRepository()
        try await mock.save(event)
        let mockResult = try await mock.fetchEvents(for: sessionID)

        // Real (in-memory DB with full migrations applied)
        let db = try MockDatabaseService()
        let sessionRepo = SessionRepository(db: db)
        try await sessionRepo.save(SessionRecord(id: sessionID, title: "Contract Test"))
        let real = HarnessEventRepository(db: db)
        try await real.save(event)
        let realResult = try await real.fetchEvents(for: sessionID)

        XCTAssertEqual(mockResult.count, 1)
        XCTAssertEqual(realResult.count, 1)
        XCTAssertEqual(mockResult.first?.id, event.id)
        XCTAssertEqual(realResult.first?.id, event.id)
        XCTAssertEqual(mockResult.first?.eventType, .ruleAppend)
        XCTAssertEqual(realResult.first?.eventType, .ruleAppend)
        XCTAssertEqual(mockResult.first?.payload, "{\"key\":\"value\"}")
        XCTAssertEqual(realResult.first?.payload, "{\"key\":\"value\"}")
    }

    // MARK: - HarnessEventRepository: type filtering

    /// Both implementations must return only events of the requested type.
    func testHarnessEventRepositoryTypeFilterContract() async throws {
        let sessionID = SessionID()
        let db = try MockDatabaseService()
        let sessionRepo = SessionRepository(db: db)
        try await sessionRepo.save(SessionRecord(id: sessionID, title: "Contract Test"))

        let mock = MockHarnessEventRepository()
        let real = HarnessEventRepository(db: db)

        let ruleEvent = HarnessEvent(sessionID: sessionID, eventType: .ruleAppend, payload: "rule")
        let errorEvent = HarnessEvent(sessionID: sessionID, eventType: .error, payload: "err")
        try await mock.save(ruleEvent)
        try await mock.save(errorEvent)
        try await real.save(ruleEvent)
        try await real.save(errorEvent)

        let mockRules = try await mock.fetchEvents(ofType: .ruleAppend, for: sessionID)
        let realRules = try await real.fetchEvents(ofType: .ruleAppend, for: sessionID)

        XCTAssertEqual(mockRules.count, 1)
        XCTAssertEqual(realRules.count, 1)
        XCTAssertEqual(mockRules.first?.eventType, .ruleAppend)
        XCTAssertEqual(realRules.first?.eventType, .ruleAppend)
        XCTAssertEqual(mockRules.first?.id, ruleEvent.id)
        XCTAssertEqual(realRules.first?.id, ruleEvent.id)
    }

    // MARK: - HarnessEventRepository: session isolation

    /// Both implementations must isolate events by sessionID — fetching for one session
    /// must not return events saved under a different session.
    func testHarnessEventRepositorySessionIsolationContract() async throws {
        let sid1 = SessionID()
        let sid2 = SessionID()
        let db = try MockDatabaseService()
        let sessionRepo = SessionRepository(db: db)
        try await sessionRepo.save(SessionRecord(id: sid1, title: "Session 1"))
        try await sessionRepo.save(SessionRecord(id: sid2, title: "Session 2"))

        let mock = MockHarnessEventRepository()
        let real = HarnessEventRepository(db: db)

        let event1 = HarnessEvent(sessionID: sid1, eventType: .tokenMilestone, payload: "s1")
        let event2 = HarnessEvent(sessionID: sid2, eventType: .tokenMilestone, payload: "s2")
        try await mock.save(event1)
        try await mock.save(event2)
        try await real.save(event1)
        try await real.save(event2)

        let mockS1 = try await mock.fetchEvents(for: sid1)
        let realS1 = try await real.fetchEvents(for: sid1)

        XCTAssertEqual(mockS1.count, 1)
        XCTAssertEqual(realS1.count, 1)
        XCTAssertEqual(mockS1.first?.payload, "s1")
        XCTAssertEqual(realS1.first?.payload, "s1")
    }

    // MARK: - HarnessEventRepository: empty fetch

    /// Both implementations must return empty for a session with no saved events.
    func testHarnessEventRepositoryFetchEmptyContract() async throws {
        let sessionID = SessionID()

        let mock = MockHarnessEventRepository()
        let mockResult = try await mock.fetchEvents(for: sessionID)

        let db = try MockDatabaseService()
        let real = HarnessEventRepository(db: db)
        let realResult = try await real.fetchEvents(for: sessionID)

        XCTAssertTrue(mockResult.isEmpty)
        XCTAssertTrue(realResult.isEmpty)
    }

    // MARK: - SessionMessageRepository: round-trip

    /// Both implementations must return the saved message on fetchMessages.
    func testSessionMessageRepositorySaveAndFetchContract() async throws {
        let sessionID = SessionID()
        let message = SessionMessage(
            sessionID: sessionID,
            role: .user,
            contentType: .model,
            content: "contract test message"
        )

        // Mock
        let mock = MockSessionMessageRepository()
        try await mock.save(message)
        let mockResult = try await mock.fetchMessages(for: sessionID, contentType: nil)

        // Real
        let db = try MockDatabaseService()
        let sessionRepo = SessionRepository(db: db)
        try await sessionRepo.save(SessionRecord(id: sessionID, title: "Contract Test"))
        let real = SessionMessageRepository(db: db)
        try await real.save(message)
        let realResult = try await real.fetchMessages(for: sessionID, contentType: nil)

        XCTAssertEqual(mockResult.count, 1)
        XCTAssertEqual(realResult.count, 1)
        XCTAssertEqual(mockResult.first?.id, message.id)
        XCTAssertEqual(realResult.first?.id, message.id)
        XCTAssertEqual(mockResult.first?.content, "contract test message")
        XCTAssertEqual(realResult.first?.content, "contract test message")
        XCTAssertEqual(mockResult.first?.role, .user)
        XCTAssertEqual(realResult.first?.role, .user)
    }

    // MARK: - SessionMessageRepository: deleteAll

    /// Both implementations must remove all messages for the given session.
    func testSessionMessageRepositoryDeleteAllContract() async throws {
        let sessionID = SessionID()
        let db = try MockDatabaseService()
        let sessionRepo = SessionRepository(db: db)
        try await sessionRepo.save(SessionRecord(id: sessionID, title: "Contract Test"))

        let mock = MockSessionMessageRepository()
        let real = SessionMessageRepository(db: db)

        for i in 0 ..< 3 {
            let msg = SessionMessage(
                sessionID: sessionID,
                role: .user,
                contentType: .model,
                content: "message \(i)"
            )
            try await mock.save(msg)
            try await real.save(msg)
        }

        try await mock.deleteAll(for: sessionID)
        try await real.deleteAll(for: sessionID)

        let mockResult = try await mock.fetchMessages(for: sessionID, contentType: nil)
        let realResult = try await real.fetchMessages(for: sessionID, contentType: nil)

        XCTAssertTrue(mockResult.isEmpty)
        XCTAssertTrue(realResult.isEmpty)
    }

    // MARK: - SessionMessageRepository: fetch empty

    /// Both implementations must return empty for a session with no saved messages.
    func testSessionMessageRepositoryFetchEmptyContract() async throws {
        let sessionID = SessionID()

        let mock = MockSessionMessageRepository()
        let mockResult = try await mock.fetchMessages(for: sessionID, contentType: nil)

        let db = try MockDatabaseService()
        let real = SessionMessageRepository(db: db)
        let realResult = try await real.fetchMessages(for: sessionID, contentType: nil)

        XCTAssertTrue(mockResult.isEmpty)
        XCTAssertTrue(realResult.isEmpty)
    }

    // MARK: - SessionMessageRepository: delete single message

    /// Both implementations must remove only the targeted message, leaving others intact.
    func testSessionMessageRepositoryDeleteSingleContract() async throws {
        let sessionID = SessionID()
        let db = try MockDatabaseService()
        let sessionRepo = SessionRepository(db: db)
        try await sessionRepo.save(SessionRecord(id: sessionID, title: "Contract Test"))

        let mock = MockSessionMessageRepository()
        let real = SessionMessageRepository(db: db)

        let keepMsg = SessionMessage(
            sessionID: sessionID,
            role: .user,
            contentType: .model,
            content: "keep"
        )
        let deleteMsg = SessionMessage(
            sessionID: sessionID,
            role: .assistant,
            contentType: .model,
            content: "delete"
        )
        try await mock.save(keepMsg)
        try await mock.save(deleteMsg)
        try await real.save(keepMsg)
        try await real.save(deleteMsg)

        try await mock.delete(id: deleteMsg.id)
        try await real.delete(id: deleteMsg.id)

        let mockResult = try await mock.fetchMessages(for: sessionID, contentType: nil)
        let realResult = try await real.fetchMessages(for: sessionID, contentType: nil)

        XCTAssertEqual(mockResult.count, 1)
        XCTAssertEqual(realResult.count, 1)
        XCTAssertEqual(mockResult.first?.content, "keep")
        XCTAssertEqual(realResult.first?.content, "keep")
    }
}
