import Foundation
import XCTest
@testable import Termura

final class SessionMessageRepositoryTests: XCTestCase {
    private var dbService: MockDatabaseService!
    private var repository: SessionMessageRepository!
    private var sessionID: SessionID!

    override func setUp() async throws {
        dbService = try MockDatabaseService()
        repository = SessionMessageRepository(db: dbService)
        sessionID = SessionID()

        // Insert a parent session row so FK constraints are satisfied.
        let session = SessionRecord(id: sessionID, title: "Test")
        let sessionRepo = SessionRepository(db: dbService)
        try await sessionRepo.save(session)
    }

    // MARK: - Helpers

    private func makeMessage(
        sessionID sid: SessionID? = nil,
        role: MessageRole = .user,
        contentType: MessageContentType = .model,
        content: String = "test content",
        tokenCount: Int = 0
    ) -> SessionMessage {
        SessionMessage(
            sessionID: sid ?? sessionID,
            role: role,
            contentType: contentType,
            content: content,
            tokenCount: tokenCount
        )
    }

    // MARK: - CRUD

    func testSaveAndFetchMessages() async throws {
        let msg1 = makeMessage(content: "first")
        let msg2 = makeMessage(content: "second")
        try await repository.save(msg1)
        try await repository.save(msg2)

        let fetched = try await repository.fetchMessages(for: sessionID, contentType: nil)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched[0].content, "first")
        XCTAssertEqual(fetched[1].content, "second")
    }

    func testFetchMessagesFiltersByContentType() async throws {
        let modelMsg = makeMessage(contentType: .model, content: "model")
        let metaMsg = makeMessage(contentType: .metadata, content: "meta")
        try await repository.save(modelMsg)
        try await repository.save(metaMsg)

        let modelOnly = try await repository.fetchMessages(for: sessionID, contentType: .model)
        XCTAssertEqual(modelOnly.count, 1)
        XCTAssertEqual(modelOnly.first?.content, "model")
    }

    func testFetchMessagesWithNilContentTypeReturnsAll() async throws {
        for ct in MessageContentType.allCases {
            try await repository.save(makeMessage(contentType: ct, content: ct.rawValue))
        }

        let all = try await repository.fetchMessages(for: sessionID, contentType: nil)
        XCTAssertEqual(all.count, MessageContentType.allCases.count)
    }

    func testDeleteSingleMessage() async throws {
        let msg1 = makeMessage(content: "keep")
        let msg2 = makeMessage(content: "delete")
        try await repository.save(msg1)
        try await repository.save(msg2)

        try await repository.delete(id: msg2.id)

        let remaining = try await repository.fetchMessages(for: sessionID, contentType: nil)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.content, "keep")
    }

    func testDeleteAllForSession() async throws {
        // Create a second session for isolation check.
        let otherID = SessionID()
        let otherSession = SessionRecord(id: otherID, title: "Other")
        let sessionRepo = SessionRepository(db: dbService)
        try await sessionRepo.save(otherSession)

        try await repository.save(makeMessage(content: "a"))
        try await repository.save(makeMessage(content: "b"))
        try await repository.save(makeMessage(sessionID: otherID, content: "other"))

        try await repository.deleteAll(for: sessionID)

        let primary = try await repository.fetchMessages(for: sessionID, contentType: nil)
        XCTAssertTrue(primary.isEmpty)

        let other = try await repository.fetchMessages(for: otherID, contentType: nil)
        XCTAssertEqual(other.count, 1)
        XCTAssertEqual(other.first?.content, "other")
    }

    // MARK: - Token counting

    func testCountTokensAggregatesCorrectly() async throws {
        try await repository.save(makeMessage(contentType: .model, tokenCount: 100))
        try await repository.save(makeMessage(contentType: .model, tokenCount: 200))
        try await repository.save(makeMessage(contentType: .model, tokenCount: 300))

        let total = try await repository.countTokens(for: sessionID, contentType: .model)
        XCTAssertEqual(total, 600)
    }

    func testCountTokensReturnsZeroForEmptySession() async throws {
        let emptyID = SessionID()
        let count = try await repository.countTokens(for: emptyID, contentType: .model)
        XCTAssertEqual(count, 0)
    }

    func testCountTokensFiltersByContentType() async throws {
        try await repository.save(makeMessage(contentType: .model, tokenCount: 100))
        try await repository.save(makeMessage(contentType: .metadata, tokenCount: 50))

        let modelTokens = try await repository.countTokens(for: sessionID, contentType: .model)
        XCTAssertEqual(modelTokens, 100)

        let metaTokens = try await repository.countTokens(for: sessionID, contentType: .metadata)
        XCTAssertEqual(metaTokens, 50)
    }

    // MARK: - Edge cases

    func testFetchForNonexistentSessionReturnsEmpty() async throws {
        let randomID = SessionID()
        let result = try await repository.fetchMessages(for: randomID, contentType: nil)
        XCTAssertTrue(result.isEmpty)
    }

    func testSaveOverwritesExistingMessage() async throws {
        let msgID = SessionMessageID()
        let original = SessionMessage(
            id: msgID,
            sessionID: sessionID,
            role: .user,
            contentType: .model,
            content: "original"
        )
        try await repository.save(original)

        let updated = SessionMessage(
            id: msgID,
            sessionID: sessionID,
            role: .user,
            contentType: .model,
            content: "updated"
        )
        try await repository.save(updated)

        let fetched = try await repository.fetchMessages(for: sessionID, contentType: nil)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.content, "updated")
    }

    func testFieldsRoundTripCorrectly() async throws {
        let msg = SessionMessage(
            sessionID: sessionID,
            role: .assistant,
            contentType: .metadata,
            content: "round trip test",
            tokenCount: 42
        )
        try await repository.save(msg)

        let fetched = try await repository.fetchMessages(for: sessionID, contentType: nil)
        let result = try XCTUnwrap(fetched.first)
        XCTAssertEqual(result.id, msg.id)
        XCTAssertEqual(result.sessionID, sessionID)
        XCTAssertEqual(result.role, .assistant)
        XCTAssertEqual(result.contentType, .metadata)
        XCTAssertEqual(result.content, "round trip test")
        XCTAssertEqual(result.tokenCount, 42)
    }

    func testAllRolesRoundTrip() async throws {
        for role in MessageRole.allCases {
            try await repository.save(makeMessage(role: role, content: role.rawValue))
        }

        let all = try await repository.fetchMessages(for: sessionID, contentType: nil)
        let roles = Set(all.map(\.role))
        XCTAssertEqual(roles, Set(MessageRole.allCases))
    }
}
