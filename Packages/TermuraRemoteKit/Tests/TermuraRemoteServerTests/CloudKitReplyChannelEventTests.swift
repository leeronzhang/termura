import Foundation
import TermuraRemoteProtocol
@testable import TermuraRemoteServer
import Testing

// Pins the D-1 contract: when `CloudKitReplyChannel.send` cannot
// hand the envelope to the gateway (CKError quota / unauthorized /
// network drop), the failure must surface on the parent transport's
// `events` stream so the Mac host (`RemoteControlController` →
// Settings UI) can show *why* the iPhone is silent — pre-fix the
// throw was caught + logged at the router and the user saw a frozen
// session list with no actionable hint.
//
// Tests resolve through deterministic stream consumption: each test
// drives exactly one failing `send` and reads exactly one event off
// `events` before tearing down — no racing timeout primitives.
@Suite("CloudKitReplyChannel transport events")
struct CloudKitReplyChannelEventTests {
    @Test("gateway.save failure yields .replyChannelSendFailed with peer + reason")
    func saveFailureSurfacesAsEvent() async throws {
        let macId = UUID()
        let phoneId = UUID()
        let failingGateway = FailingSaveGateway(
            saveError: CloudKitGatewayError.backingFailure(reason: "simulated CK quota")
        )
        let transport = CloudKitTransport(
            name: "mac",
            deviceId: macId,
            gateway: failingGateway,
            configuration: .init(pollInterval: .seconds(3600)),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        let handler = StashingHandler()
        try await transport.start(handler: handler)

        // Drive an inbound record so the transport materialises a reply
        // channel for `phoneId`. The gateway swallows the `save` of the
        // inbound mailbox check via the `fetch` path (which we leave
        // healthy); only the *outbound* `save` fails.
        await failingGateway.allowFetchOnly()
        try await failingGateway.injectInbound(CloudKitEnvelopeRecord(
            id: "phone-msg",
            payload: .plaintext(Envelope(kind: .ping, payload: Data())),
            targetDeviceId: macId,
            sourceDeviceId: phoneId,
            createdAt: Date(timeIntervalSince1970: 2000)
        ))
        await transport.ingestPushNotification()
        let captured = await handler.lastReplyChannel
        let channel = try #require(captured)

        // Now arm the gateway so the *reply* save throws, then kick off
        // a send and drain the first event.
        await failingGateway.failNextSave()
        let stream = transport.events
        var iterator = stream.makeAsyncIterator()
        await #expect(throws: TransportError.self) {
            try await channel.send(Envelope(kind: .pong, payload: Data()))
        }
        let event = await iterator.next()
        let observed = try #require(event)
        guard case let .replyChannelSendFailed(peer, reason, occurredAt) = observed else {
            Issue.record("expected .replyChannelSendFailed, got \(observed)")
            return
        }
        #expect(peer == phoneId, "event must carry the peer device id of the failed reply")
        #expect(reason.contains("simulated CK quota"), "event reason must surface the gateway error")
        #expect(occurredAt == Date(timeIntervalSince1970: 1000),
                "occurredAt must come from the transport's injected clock so consumers do not have to call Date() at the drain hop")
        await transport.stop()
    }

    @Test("default RemoteTransport.events finishes immediately for non-CloudKit conformers")
    func defaultStreamFinishesImmediately() async {
        struct StubTransport: RemoteTransport {
            let name = "stub"
            func start(handler _: any EnvelopeHandler) async throws {}
            func stop() async {}
        }
        var observed = 0
        for await _ in StubTransport().events {
            observed += 1
        }
        // The protocol-extension default yields nothing and finishes;
        // a non-CloudKit transport (LAN, mocks) drains cleanly without
        // forcing the consumer to special-case missing events.
        #expect(observed == 0)
    }
}

/// Test double layered on top of `InMemoryCloudKitDatabaseGateway`
/// that lets a single test toggle whether the next `save` should
/// throw without affecting `fetch` (used to materialise the inbound
/// reply channel before exercising the outbound failure path).
actor FailingSaveGateway: CloudKitDatabaseGateway {
    private let inner = InMemoryCloudKitDatabaseGateway()
    private var saveError: any Error
    private var saveMode: SaveMode = .alwaysFail

    private enum SaveMode {
        case alwaysFail
        case allowAll
        case failNext
    }

    init(saveError: any Error) {
        self.saveError = saveError
    }

    func allowFetchOnly() {
        saveMode = .allowAll
    }

    func failNextSave() {
        saveMode = .failNext
    }

    /// Bypasses the public `save` so a test can pre-stage records in
    /// the mailbox without tripping the failure switch.
    func injectInbound(_ record: CloudKitEnvelopeRecord) async throws {
        try await inner.save(record)
    }

    func save(_ record: CloudKitEnvelopeRecord) async throws {
        switch saveMode {
        case .alwaysFail:
            throw saveError
        case .failNext:
            saveMode = .allowAll
            throw saveError
        case .allowAll:
            try await inner.save(record)
        }
    }

    func fetch(targetDeviceId: UUID, since: Date) async throws -> CloudKitFetchPage {
        try await inner.fetch(targetDeviceId: targetDeviceId, since: since)
    }

    func delete(id: String) async throws {
        try await inner.delete(id: id)
    }
}
