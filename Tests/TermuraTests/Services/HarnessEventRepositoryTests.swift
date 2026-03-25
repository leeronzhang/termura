import Foundation
import XCTest
@testable import Termura

final class HarnessEventRepositoryTests: XCTestCase {
    private var dbService: MockDatabaseService!
    private var repository: HarnessEventRepository!
    private var sessionID: SessionID!

    override func setUp() async throws {
        dbService = try MockDatabaseService()
        repository = HarnessEventRepository(db: dbService)
        sessionID = SessionID()

        // Insert a parent session row so FK constraints are satisfied.
        let session = SessionRecord(id: sessionID, title: "Test")
        let sessionRepo = SessionRepository(db: dbService)
        try await sessionRepo.save(session)
    }

    // MARK: - Helpers

    private func makeEvent(
        sessionID sid: SessionID? = nil,
        eventType: HarnessEventType = .ruleAppend,
        payload: String = "{}"
    ) -> HarnessEvent {
        HarnessEvent(
            sessionID: sid ?? sessionID,
            eventType: eventType,
            payload: payload
        )
    }

    // MARK: - CRUD

    func testSaveAndFetchEvents() async throws {
        let event = makeEvent(payload: "{\"key\":\"value\"}")
        try await repository.save(event)

        let fetched = try await repository.fetchEvents(for: sessionID)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.payload, "{\"key\":\"value\"}")
    }

    func testFetchEventsOrderedByCreatedAt() async throws {
        let early = HarnessEvent(
            sessionID: sessionID,
            eventType: .error,
            payload: "first",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        let middle = HarnessEvent(
            sessionID: sessionID,
            eventType: .error,
            payload: "second",
            createdAt: Date(timeIntervalSince1970: 2000)
        )
        let late = HarnessEvent(
            sessionID: sessionID,
            eventType: .error,
            payload: "third",
            createdAt: Date(timeIntervalSince1970: 3000)
        )
        // Save out of order.
        try await repository.save(late)
        try await repository.save(early)
        try await repository.save(middle)

        let fetched = try await repository.fetchEvents(for: sessionID)
        XCTAssertEqual(fetched.map(\.payload), ["first", "second", "third"])
    }

    func testFetchEventsForNonexistentSessionReturnsEmpty() async throws {
        let randomID = SessionID()
        let result = try await repository.fetchEvents(for: randomID)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Type filtering

    func testFetchByTypeFiltersCorrectly() async throws {
        try await repository.save(makeEvent(eventType: .ruleAppend, payload: "rule"))
        try await repository.save(makeEvent(eventType: .error, payload: "err"))

        let rules = try await repository.fetchEvents(ofType: .ruleAppend, for: sessionID)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.payload, "rule")
    }

    func testFetchByTypeReturnsEmptyWhenNoMatch() async throws {
        try await repository.save(makeEvent(eventType: .tokenMilestone))

        let handoffs = try await repository.fetchEvents(ofType: .sessionHandoff, for: sessionID)
        XCTAssertTrue(handoffs.isEmpty)
    }

    // MARK: - Round-trip

    func testAllEventTypesRoundTrip() async throws {
        for eventType in HarnessEventType.allCases {
            try await repository.save(makeEvent(eventType: eventType, payload: eventType.rawValue))
        }

        let all = try await repository.fetchEvents(for: sessionID)
        let types = Set(all.map(\.eventType))
        XCTAssertEqual(types, Set(HarnessEventType.allCases))
    }

    func testFieldsRoundTripCorrectly() async throws {
        let event = HarnessEvent(
            sessionID: sessionID,
            eventType: .sessionHandoff,
            payload: "{\"summary\":\"test\"}"
        )
        try await repository.save(event)

        let fetched = try await repository.fetchEvents(for: sessionID)
        let result = try XCTUnwrap(fetched.first)
        XCTAssertEqual(result.id, event.id)
        XCTAssertEqual(result.sessionID, sessionID)
        XCTAssertEqual(result.eventType, .sessionHandoff)
        XCTAssertEqual(result.payload, "{\"summary\":\"test\"}")
    }
}
