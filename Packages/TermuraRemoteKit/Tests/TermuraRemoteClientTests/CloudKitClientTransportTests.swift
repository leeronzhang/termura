import Foundation
@testable import TermuraRemoteClient
import TermuraRemoteProtocol
import Testing

@Suite("CloudKitClientTransport")
struct CloudKitClientTransportTests {
    @Test("send writes a record addressed to the peer")
    func sendAddressesPeer() async throws {
        let phoneId = UUID()
        let macId = UUID()
        let gateway = InMemoryCloudKitDatabaseGateway()
        let transport = CloudKitClientTransport(
            localDeviceId: phoneId,
            peerDeviceId: macId,
            gateway: gateway,
            configuration: .init(pollInterval: .seconds(3600)),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        try await transport.connect()
        try await transport.send(Envelope(kind: .ping, payload: Data()))

        let macInbox = try await gateway.fetch(targetDeviceId: macId, since: .distantPast)
        #expect(macInbox.records.count == 1)
        #expect(macInbox.records.first?.sourceDeviceId == phoneId)
    }

    @Test("ingestPushNotification surfaces queued envelope to receive()")
    func receiveAfterPush() async throws {
        let phoneId = UUID()
        let macId = UUID()
        let gateway = InMemoryCloudKitDatabaseGateway()
        let transport = CloudKitClientTransport(
            localDeviceId: phoneId,
            peerDeviceId: macId,
            gateway: gateway,
            configuration: .init(pollInterval: .seconds(3600)),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        try await transport.connect()
        try await gateway.save(CloudKitEnvelopeRecord(
            id: "incoming",
            payload: .plaintext(Envelope(kind: .pong, payload: Data())),
            targetDeviceId: phoneId,
            sourceDeviceId: macId,
            createdAt: Date(timeIntervalSince1970: 2000)
        ))
        await transport.ingestPushNotification()

        let received = try await transport.receive()
        #expect(received.kind == .pong)
    }

    @Test("disconnect resumes pending receivers with notConnected")
    func disconnectResumesReceivers() async throws {
        let gateway = InMemoryCloudKitDatabaseGateway()
        let transport = CloudKitClientTransport(
            localDeviceId: UUID(),
            peerDeviceId: UUID(),
            gateway: gateway,
            configuration: .init(pollInterval: .seconds(3600)),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        try await transport.connect()

        let receiver = Task { try await transport.receive() }

        // Yield until the receiver has registered as a waiter on the actor.
        await Task.yield()
        await Task.yield()

        await transport.disconnect()

        do {
            _ = try await receiver.value
            Issue.record("receive() should have thrown after disconnect")
        } catch ClientTransportError.notConnected {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("send before connect throws notConnected")
    func sendBeforeConnect() async {
        let transport = CloudKitClientTransport(
            localDeviceId: UUID(),
            peerDeviceId: UUID(),
            gateway: InMemoryCloudKitDatabaseGateway()
        )
        await #expect(throws: ClientTransportError.notConnected) {
            try await transport.send(Envelope(kind: .ping, payload: Data()))
        }
    }

    // D-1 — gateway.save failure is the moral equivalent of a fatal
    // NWError on the WebSocket transport. iOS reconnect controller
    // drives recovery uniformly off `events`, so the CloudKit client
    // must yield `.disconnected` on the same hop as the throw — not
    // wait for the next poll-health snapshot. Pre-fix the iOS user
    // saw "no reply received" with no signal that the *outbound*
    // write itself had failed.
    @Test("send save failure yields .disconnected with sendFailure reason")
    func sendFailureSurfacesAsEvent() async throws {
        let phoneId = UUID()
        let macId = UUID()
        let gateway = ClientFailingSaveGateway(
            saveError: CloudKitGatewayError.backingFailure(reason: "simulated CK quota")
        )
        let transport = CloudKitClientTransport(
            localDeviceId: phoneId,
            peerDeviceId: macId,
            gateway: gateway,
            configuration: .init(pollInterval: .seconds(3600)),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        try await transport.connect()
        var iterator = transport.events.makeAsyncIterator()
        await #expect(throws: ClientTransportError.self) {
            try await transport.send(Envelope(kind: .ping, payload: Data()))
        }
        let event = await iterator.next()
        let observed = try #require(event)
        guard case let .disconnected(reason) = observed else {
            Issue.record("expected .disconnected, got \(observed)")
            return
        }
        guard case let .sendFailure(text) = reason else {
            Issue.record("expected .sendFailure reason, got \(reason)")
            return
        }
        #expect(text.contains("simulated CK quota"))
    }

    @Test("send before connect yields .disconnected with notConnected reason")
    func sendBeforeConnectYieldsEvent() async throws {
        let transport = CloudKitClientTransport(
            localDeviceId: UUID(),
            peerDeviceId: UUID(),
            gateway: InMemoryCloudKitDatabaseGateway()
        )
        var iterator = transport.events.makeAsyncIterator()
        await #expect(throws: ClientTransportError.notConnected) {
            try await transport.send(Envelope(kind: .ping, payload: Data()))
        }
        let event = await iterator.next()
        let observed = try #require(event)
        guard case let .disconnected(reason) = observed,
              case .notConnected = reason
        else {
            Issue.record("expected .disconnected(.notConnected), got \(observed)")
            return
        }
    }

    // Regression — previously the iOS connect path advanced the cursor
    // to the max `createdAt` of the existing inbox, dropping any messages
    // the Mac queued while the iPhone was offline (review item D6/U3/U6).
    // Fix: the initial fetch's records flow into the receive() queue
    // before the poll loop starts, and quarantined entries are deleted
    // so they don't loop.
    @Test("connect drains inbox backlog into receive() (offline iPhone recovery)")
    func connectDrainsBacklog() async throws {
        let phoneId = UUID()
        let macId = UUID()
        let queuedRecord = CloudKitEnvelopeRecord(
            id: "queued-while-offline",
            payload: .plaintext(Envelope(kind: .pong, payload: Data())),
            targetDeviceId: phoneId,
            sourceDeviceId: macId,
            createdAt: Date(timeIntervalSince1970: 800)
        )
        let gateway = InMemoryCloudKitDatabaseGateway(seed: [queuedRecord])
        let transport = CloudKitClientTransport(
            localDeviceId: phoneId,
            peerDeviceId: macId,
            gateway: gateway,
            configuration: .init(pollInterval: .seconds(3600)),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        try await transport.connect()
        let received = try await transport.receive()
        #expect(received.kind == .pong, "Backlog must surface to receive(), not be skipped")
    }
}

/// Test double layered on top of `InMemoryCloudKitDatabaseGateway`
/// that fails every `save` while leaving `fetch` healthy. Used by
/// the D-1 send-failure event tests so the transport can `connect`
/// against a known-good fetch path before the outbound `save`
/// throws.
actor ClientFailingSaveGateway: CloudKitDatabaseGateway {
    private let inner = InMemoryCloudKitDatabaseGateway()
    private let saveError: any Error

    init(saveError: any Error) {
        self.saveError = saveError
    }

    func save(_: CloudKitEnvelopeRecord) async throws {
        throw saveError
    }

    func fetch(targetDeviceId: UUID, since: Date) async throws -> CloudKitFetchPage {
        try await inner.fetch(targetDeviceId: targetDeviceId, since: since)
    }

    func delete(id: String) async throws {
        try await inner.delete(id: id)
    }
}
