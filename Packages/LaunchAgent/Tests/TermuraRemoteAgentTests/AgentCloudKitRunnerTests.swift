import Foundation
@testable import termura_remote_agent
import TermuraRemoteProtocol
import Testing

@Suite("AgentCloudKitRunner.pollOnce")
struct AgentCloudKitRunnerTests {
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

    private static func record(
        id: String,
        createdAt: Date,
        sourceDeviceId: UUID = UUID()
    ) -> CloudKitEnvelopeRecord {
        let envelope = Envelope(
            version: ProtocolVersion.current,
            kind: .ping,
            payload: Data()
        )
        return CloudKitEnvelopeRecord(
            id: id,
            payload: .plaintext(envelope),
            targetDeviceId: UUID(),
            sourceDeviceId: sourceDeviceId,
            createdAt: createdAt
        )
    }

    @Test("happy path: every record advances cursor through dispatcher")
    func runnerProcessesAllRecords() async throws {
        let macId = UUID()
        let r1 = Self.record(id: "R1", createdAt: Date(timeIntervalSince1970: 100))
        let r2 = Self.record(id: "R2", createdAt: Date(timeIntervalSince1970: 200))
        let gateway = RecordingGateway(fetchResult: [r2, r1])
        let cursor = AgentCursorStore(serviceName: Self.freshService("runner.cursor"))
        let quarantine = AgentQuarantineStore(serviceName: Self.freshService("runner.quarantine"))
        let dispatcher = AgentAppDispatcher(
            cursorStore: cursor,
            quarantineStore: quarantine,
            gateway: gateway,
            attemptThreshold: 3
        )
        let holder = ConnectionHolder { _, completion in
            completion(true, "ok")
        }
        await dispatcher.bind(connection: holder)
        let runner = AgentCloudKitRunner(
            macDeviceId: macId,
            gateway: gateway,
            cursorStore: cursor,
            quarantineStore: quarantine,
            dispatcher: dispatcher
        )
        await runner.pollOnce()
        let finalCursor = await cursor.read()
        #expect(finalCursor == r2.createdAt)
        let deletes = await gateway.deletedIds()
        // sorted ascending: R1 first then R2
        #expect(deletes == ["R1", "R2"])
    }

    @Test("blocked record halts the poll; subsequent records are not delivered")
    func haltsOnFirstFailure() async throws {
        let macId = UUID()
        let r1 = Self.record(id: "R1", createdAt: Date(timeIntervalSince1970: 100))
        let r2 = Self.record(id: "R2", createdAt: Date(timeIntervalSince1970: 200))
        let r3 = Self.record(id: "R3", createdAt: Date(timeIntervalSince1970: 300))
        let gateway = RecordingGateway(fetchResult: [r1, r2, r3])
        let cursor = AgentCursorStore(serviceName: Self.freshService("runner.halt.cursor"))
        let quarantine = AgentQuarantineStore(serviceName: Self.freshService("runner.halt.quarantine"))
        let dispatcher = AgentAppDispatcher(
            cursorStore: cursor,
            quarantineStore: quarantine,
            gateway: gateway,
            attemptThreshold: 5
        )
        let calls = CallCounter()
        let holder = ConnectionHolder { _, completion in
            let box = ReplyShim(reply: completion)
            Task {
                let count = await calls.bumpAndReturn()
                if count == 2 {
                    box.invoke(success: false, reason: "decode_failed")
                } else {
                    box.invoke(success: true, reason: "ok")
                }
            }
        }
        await dispatcher.bind(connection: holder)
        let runner = AgentCloudKitRunner(
            macDeviceId: macId,
            gateway: gateway,
            cursorStore: cursor,
            quarantineStore: quarantine,
            dispatcher: dispatcher
        )
        await runner.pollOnce()
        let finalCursor = await cursor.read()
        #expect(finalCursor == r1.createdAt)
        let deletes = await gateway.deletedIds()
        #expect(deletes == ["R1"])
    }

    @Test("blocked record re-enters dispatcher on each subsequent poll until threshold reached")
    func blockedRecordIsReDispatchedUntilThreshold() async throws {
        let macId = UUID()
        let r1 = Self.record(id: "R1", createdAt: Date(timeIntervalSince1970: 100))
        let gateway = RecordingGateway(fetchResult: [r1])
        let cursorService = Self.freshService("runner.retry.cursor")
        let quarantineService = Self.freshService("runner.retry.quarantine")
        let cursor = AgentCursorStore(serviceName: cursorService)
        let quarantine = AgentQuarantineStore(serviceName: quarantineService)
        let dispatcher = AgentAppDispatcher(
            cursorStore: cursor,
            quarantineStore: quarantine,
            gateway: gateway,
            attemptThreshold: 3
        )
        let calls = CallCounter()
        let holder = ConnectionHolder { _, completion in
            let box = ReplyShim(reply: completion)
            Task {
                _ = await calls.bumpAndReturn()
                box.invoke(success: false, reason: "decode_failed")
            }
        }
        await dispatcher.bind(connection: holder)
        let runner = AgentCloudKitRunner(
            macDeviceId: macId,
            gateway: gateway,
            cursorStore: cursor,
            quarantineStore: quarantine,
            dispatcher: dispatcher
        )
        // Round 1: first failure → .retrying (NOT yet quarantined).
        await runner.pollOnce()
        #expect(await calls.snapshot() == 1)
        #expect(await quarantine.contains(recordName: "R1") == false)
        #expect(await quarantine.state(for: "R1") == .retrying)
        // Round 2: same record must re-enter dispatcher → second
        // attempt → still .retrying.
        await runner.pollOnce()
        #expect(await calls.snapshot() == 2)
        #expect(await quarantine.contains(recordName: "R1") == false)
        // Round 3: third attempt promotes to .quarantined.
        await runner.pollOnce()
        #expect(await calls.snapshot() == 3)
        #expect(await quarantine.contains(recordName: "R1") == true)
        #expect(await quarantine.state(for: "R1") == .quarantined)
        // Round 4: runner filter must now exclude R1; dispatcher
        // must NOT see it again.
        await runner.pollOnce()
        #expect(await calls.snapshot() == 3)
    }

    @Test("quarantined records are filtered before dispatch")
    func quarantineFiltersFetchResults() async throws {
        let macId = UUID()
        let r1 = Self.record(id: "R1", createdAt: Date(timeIntervalSince1970: 100))
        let r2 = Self.record(id: "R2", createdAt: Date(timeIntervalSince1970: 200))
        let gateway = RecordingGateway(fetchResult: [r1, r2])
        let quarantineService = Self.freshService("runner.qfilter.quarantine")
        let cursorService = Self.freshService("runner.qfilter.cursor")
        let cursor = AgentCursorStore(serviceName: cursorService)
        let quarantine = AgentQuarantineStore(serviceName: quarantineService)
        try await quarantine.add(QuarantineEntry(
            recordName: "R1",
            createdAt: r1.createdAt,
            reasonCode: "decode_failed",
            attempts: 5,
            firstSeenAt: Date(),
            state: .quarantined
        ))
        let dispatcher = AgentAppDispatcher(
            cursorStore: cursor,
            quarantineStore: quarantine,
            gateway: gateway,
            attemptThreshold: 5
        )
        await dispatcher.bind(connection: ConnectionHolder { _, completion in
            completion(true, "ok")
        })
        let runner = AgentCloudKitRunner(
            macDeviceId: macId,
            gateway: gateway,
            cursorStore: cursor,
            quarantineStore: quarantine,
            dispatcher: dispatcher
        )
        await runner.pollOnce()
        let deletes = await gateway.deletedIds()
        // R1 was filtered out by quarantine; only R2 reached dispatcher
        #expect(deletes == ["R2"])
    }
}

actor CallCounter {
    private var count = 0
    func bumpAndReturn() -> Int {
        count += 1
        return count
    }

    func snapshot() -> Int { count }
}

/// Wraps the dispatcher reply closure so it can be safely captured
/// across a Task hop. The closure is invoked exactly once.
struct ReplyShim: @unchecked Sendable {
    let reply: @Sendable (Bool, String) -> Void

    func invoke(success: Bool, reason: String) {
        reply(success, reason)
    }
}
