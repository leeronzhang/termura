import Foundation

/// Test double for `HarnessEventRepositoryProtocol`.
actor MockHarnessEventRepository: HarnessEventRepositoryProtocol {
    var savedEvents: [HarnessEvent] = []

    func fetchEvents(for sessionID: SessionID) async throws -> [HarnessEvent] {
        savedEvents.filter { $0.sessionID == sessionID }
    }

    func save(_ event: HarnessEvent) async throws {
        savedEvents.append(event)
    }

    func fetchEvents(
        ofType type: HarnessEventType,
        for sessionID: SessionID
    ) async throws -> [HarnessEvent] {
        savedEvents.filter { $0.sessionID == sessionID && $0.eventType == type }
    }
}
