import Foundation
@testable import termura_remote_agent
import TermuraRemoteProtocol
import Testing

@Suite("AgentAppDispatcher.consume")
struct AgentAppDispatcherTests {
    private static func freshService(_ prefix: String) -> String {
        "com.termura.agent.\(prefix).test.\(UUID().uuidString)"
    }

    private static func wipe(serviceName: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func sampleItem(
        recordName: String = "REC-A",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> AgentMailboxItem {
        AgentMailboxItem(
            recordName: recordName,
            createdAt: createdAt,
            sourceDeviceId: UUID(),
            payloadKind: .plaintext,
            payloadData: Data([0x01])
        )
    }

    private struct Fixture {
        let dispatcher: AgentAppDispatcher
        let cursor: AgentCursorStore
        let quarantine: AgentQuarantineStore
        let gateway: RecordingGateway
        let cursorService: String
        let quarantineService: String
    }

    private static func makeFixture(
        replyHandler: @escaping @Sendable (AgentMailboxItem) -> AppMailboxReplyValues,
        gateway: RecordingGateway = RecordingGateway(),
        attemptThreshold: Int = 3
    ) -> Fixture {
        let cursorService = freshService("dispatcher.cursor")
        let quarantineService = freshService("dispatcher.quarantine")
        let cursor = AgentCursorStore(serviceName: cursorService)
        let quarantine = AgentQuarantineStore(serviceName: quarantineService)
        let dispatcher = AgentAppDispatcher(
            cursorStore: cursor,
            quarantineStore: quarantine,
            gateway: gateway,
            attemptThreshold: attemptThreshold
        )
        return Fixture(
            dispatcher: dispatcher,
            cursor: cursor,
            quarantine: quarantine,
            gateway: gateway,
            cursorService: cursorService,
            quarantineService: quarantineService
        )
    }

    @Test("happy path: deliver→delete→advance")
    func happyPath() async throws {
        let fixture = Self.makeFixture { _ in AppMailboxReplyValues(success: true, reasonCode: "ok") }
        let item = Self.sampleItem()
        await fixture.dispatcher.bind(connection: makeConnection(reply: { _ in
            AppMailboxReplyValues(success: true, reasonCode: "ok")
        }))
        let outcome = await fixture.dispatcher.consume(item: item)
        if case let .advanced(date) = outcome {
            #expect(date == item.createdAt)
        } else {
            Issue.record("expected .advanced, got \(outcome)")
        }
        let deletes = await fixture.gateway.deletedIds()
        #expect(deletes == [item.recordName])
        let cursor = await fixture.cursor.read()
        #expect(cursor == item.createdAt)
        Self.wipe(serviceName: fixture.cursorService)
        Self.wipe(serviceName: fixture.quarantineService)
    }

    @Test("retry path: deliver fails with countable reason → blocked, no delete, no advance")
    func deliverFailureBlocks() async throws {
        let fixture = Self.makeFixture { _ in
            AppMailboxReplyValues(success: false, reasonCode: "decode_failed")
        }
        await fixture.dispatcher.bind(connection: makeConnection(reply: { _ in
            AppMailboxReplyValues(success: false, reasonCode: "decode_failed")
        }))
        let item = Self.sampleItem()
        let outcome = await fixture.dispatcher.consume(item: item)
        if case let .blocked(reason) = outcome {
            #expect(reason == "decode_failed")
        } else {
            Issue.record("expected .blocked, got \(outcome)")
        }
        let deletes = await fixture.gateway.deletedIds()
        #expect(deletes.isEmpty)
        let cursor = await fixture.cursor.read()
        #expect(cursor == Date(timeIntervalSince1970: 0))
        Self.wipe(serviceName: fixture.cursorService)
        Self.wipe(serviceName: fixture.quarantineService)
    }

    @Test("after attemptThreshold attempts the record is quarantined and cursor is force-advanced")
    func quarantineUpgrade() async throws {
        let fixture = Self.makeFixture(replyHandler: { _ in
            AppMailboxReplyValues(success: false, reasonCode: "decode_failed")
        }, attemptThreshold: 3)
        await fixture.dispatcher.bind(connection: makeConnection(reply: { _ in
            AppMailboxReplyValues(success: false, reasonCode: "decode_failed")
        }))
        let item = Self.sampleItem()
        for _ in 0 ..< 2 {
            let outcome = await fixture.dispatcher.consume(item: item)
            #expect({ if case .blocked = outcome { true } else { false } }())
        }
        let final = await fixture.dispatcher.consume(item: item)
        if case let .quarantined(name, reason) = final {
            #expect(name == item.recordName)
            #expect(reason == "decode_failed")
        } else {
            Issue.record("expected .quarantined, got \(final)")
        }
        let cursor = await fixture.cursor.read()
        #expect(cursor == item.createdAt)
        let inQuarantine = await fixture.quarantine.contains(recordName: item.recordName)
        #expect(inQuarantine)
        Self.wipe(serviceName: fixture.cursorService)
        Self.wipe(serviceName: fixture.quarantineService)
    }

    @Test("non-attempt reasons (shutdown / connection_invalidated) never accumulate quarantine attempts")
    func nonAttemptReasons() async throws {
        let fixture = Self.makeFixture(replyHandler: { _ in
            AppMailboxReplyValues(success: false, reasonCode: "shutdown")
        }, attemptThreshold: 2)
        await fixture.dispatcher.bind(connection: makeConnection(reply: { _ in
            AppMailboxReplyValues(success: false, reasonCode: "shutdown")
        }))
        let item = Self.sampleItem()
        for _ in 0 ..< 5 {
            let outcome = await fixture.dispatcher.consume(item: item)
            if case .quarantined = outcome {
                Issue.record("shutdown reason should never be promoted to quarantine")
            }
        }
        let attempts = await fixture.quarantine.attempts(for: item.recordName)
        #expect(attempts == 0)
        Self.wipe(serviceName: fixture.cursorService)
        Self.wipe(serviceName: fixture.quarantineService)
    }

    @Test("delete failure returns blocked and does not advance cursor")
    func deleteFailureBlocks() async throws {
        let gateway = RecordingGateway(deleteFailure: true)
        let fixture = Self.makeFixture(
            replyHandler: { _ in AppMailboxReplyValues(success: true, reasonCode: "ok") },
            gateway: gateway
        )
        await fixture.dispatcher.bind(connection: makeConnection(reply: { _ in
            AppMailboxReplyValues(success: true, reasonCode: "ok")
        }))
        let item = Self.sampleItem()
        let outcome = await fixture.dispatcher.consume(item: item)
        if case let .blocked(reason) = outcome {
            #expect(reason == "delete_failed")
        } else {
            Issue.record("expected .blocked(delete_failed), got \(outcome)")
        }
        let cursor = await fixture.cursor.read()
        #expect(cursor == Date(timeIntervalSince1970: 0))
        Self.wipe(serviceName: fixture.cursorService)
        Self.wipe(serviceName: fixture.quarantineService)
    }

    private func makeConnection(
        reply: @escaping @Sendable (AgentMailboxItem) -> AppMailboxReplyValues
    ) -> ConnectionHolder {
        ConnectionHolder { _, completion in
            // The proxy in production translates XPCMailboxItem into a
            // reply via the main app; in tests we route the canned reply
            // directly so we can drive consume() through every code path.
            let stub = AgentMailboxItem(
                recordName: "test",
                createdAt: Date(),
                sourceDeviceId: UUID(),
                payloadKind: .plaintext,
                payloadData: Data()
            )
            let result = reply(stub)
            completion(result.success, result.reasonCode)
        }
    }
}

actor RecordingGateway: CloudKitDatabaseGateway {
    private(set) var saved: [CloudKitEnvelopeRecord] = []
    private(set) var deletes: [String] = []
    private let deleteFailure: Bool
    private let fetchResult: [CloudKitEnvelopeRecord]

    init(deleteFailure: Bool = false, fetchResult: [CloudKitEnvelopeRecord] = []) {
        self.deleteFailure = deleteFailure
        self.fetchResult = fetchResult
    }

    func save(_ record: CloudKitEnvelopeRecord) async throws {
        saved.append(record)
    }

    func fetch(targetDeviceId: UUID, since: Date) async throws -> CloudKitFetchPage {
        _ = targetDeviceId
        _ = since
        return CloudKitFetchPage(records: fetchResult)
    }

    func delete(id: String) async throws {
        if deleteFailure { throw NSError(domain: "test", code: 1) }
        deletes.append(id)
    }

    func deletedIds() -> [String] { deletes }
    func savedRecords() -> [CloudKitEnvelopeRecord] { saved }
}
