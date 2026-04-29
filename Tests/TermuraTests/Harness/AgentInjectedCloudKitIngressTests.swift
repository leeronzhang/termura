#if HARNESS_ENABLED
import Foundation
@testable import Termura
import Testing
import TermuraRemoteProtocol
@testable import TermuraRemoteServer

@Suite("AgentInjectedCloudKitIngress.ingest")
struct AgentInjectedCloudKitIngressTests {
    private struct StubAdapter: RemoteSessionsAdapter {
        func listSessions() async -> [RemoteSessionInfo] { [] }
        func executeCommand(line _: String, sessionId _: UUID) async throws -> CommandRunResult {
            CommandRunResult(stdout: "", exitCode: 0)
        }
    }

    private actor RecordingGateway: CloudKitDatabaseGateway {
        private(set) var saved: [CloudKitEnvelopeRecord] = []
        func save(_ record: CloudKitEnvelopeRecord) async throws {
            saved.append(record)
        }
        func fetch(targetDeviceId: UUID, since: Date) async throws -> [CloudKitEnvelopeRecord] { [] }
        func delete(id: String) async throws { _ = id }
        func snapshot() -> [CloudKitEnvelopeRecord] { saved }
    }

    private static func makeIngress(
        seed: [PairedDevice] = [],
        gateway: RecordingGateway = RecordingGateway(),
        macDeviceId: UUID = UUID()
    ) -> (AgentInjectedCloudKitIngress, RemoteEnvelopeRouter, InMemoryPairedDeviceStore, RecordingGateway, PairingService) {
        let identity = DeviceIdentity.generate()
        let issuer = PairingTokenIssuer(
            lifetime: 300,
            randomBytes: { count in Data(repeating: 0xAA, count: count) }
        )
        let store = InMemoryPairedDeviceStore(seed: seed)
        let pairingService = PairingService(
            identity: identity,
            tokenIssuer: issuer,
            store: store,
            serviceName: "test-mac"
        )
        let snapshotPublisher = SnapshotPublisher(attachmentStore: NullAttachmentStore())
        let router = RemoteEnvelopeRouter(
            adapter: StubAdapter(),
            pairingService: pairingService,
            policy: DangerousCommandPolicy(),
            snapshotPublisher: snapshotPublisher,
            codec: JSONRemoteCodec()
        )
        let gate = TrustedSourceGate(store: store)
        let ingress = AgentInjectedCloudKitIngress(
            router: router,
            gate: gate,
            pairKeyStore: InMemoryPairKeyStore(),
            gateway: gateway,
            macDeviceId: macDeviceId,
            codec: JSONRemoteCodec()
        )
        return (ingress, router, store, gateway, pairingService)
    }

    private static func sampleItem(
        kind: AgentMailboxItem.PayloadKind,
        payload: Data,
        sourceDeviceId: UUID = UUID()
    ) -> AgentMailboxItem {
        AgentMailboxItem(
            recordName: "REC",
            createdAt: Date(timeIntervalSince1970: 1_000),
            sourceDeviceId: sourceDeviceId,
            payloadKind: kind,
            payloadData: payload
        )
    }

    @Test("plaintext + unknown source → terminal unknown_source")
    func plaintextUnknownSource() async throws {
        let (ingress, _, _, _, _) = Self.makeIngress()
        let envelope = Envelope(version: ProtocolVersion.current, kind: .sessionListRequest, payload: Data())
        let payload = try JSONEncoder().encode(envelope)
        let item = Self.sampleItem(kind: .plaintext, payload: payload)
        let reply = await ingress.ingest(item: item)
        #expect(reply.success == true)
        #expect(reply.reasonCode == "unknown_source")
    }

    @Test("plaintext + revoked source → terminal revoked")
    func plaintextRevoked() async throws {
        let identity = DeviceIdentity.generate()
        let cloudId = DeviceIdentity.deriveDeviceId(from: identity.publicKeyData)
        let device = PairedDevice(
            nickname: "iPhone",
            publicKey: identity.publicKeyData,
            pairedAt: Date(timeIntervalSince1970: 100),
            revokedAt: Date(timeIntervalSince1970: 500),
            cloudSourceDeviceId: cloudId
        )
        let (ingress, _, _, _, _) = Self.makeIngress(seed: [device])
        let envelope = Envelope(version: ProtocolVersion.current, kind: .sessionListRequest, payload: Data())
        let payload = try JSONEncoder().encode(envelope)
        let item = Self.sampleItem(kind: .plaintext, payload: payload, sourceDeviceId: cloudId)
        let reply = await ingress.ingest(item: item)
        #expect(reply.success == true)
        #expect(reply.reasonCode == "revoked")
    }

    @Test("plaintext business + knownActive → ok")
    func plaintextBusinessKnownActive() async throws {
        let identity = DeviceIdentity.generate()
        let cloudId = DeviceIdentity.deriveDeviceId(from: identity.publicKeyData)
        let device = PairedDevice(
            nickname: "iPhone",
            publicKey: identity.publicKeyData,
            pairedAt: Date(timeIntervalSince1970: 100),
            negotiatedCodec: .json,
            pairingId: UUID(),
            cloudSourceDeviceId: cloudId
        )
        let (ingress, _, _, _, _) = Self.makeIngress(seed: [device])
        let envelope = Envelope(version: ProtocolVersion.current, kind: .sessionListRequest, payload: Data())
        let payload = try JSONEncoder().encode(envelope)
        let item = Self.sampleItem(kind: .plaintext, payload: payload, sourceDeviceId: cloudId)
        let reply = await ingress.ingest(item: item)
        #expect(reply.success == true)
        #expect(reply.reasonCode == "ok")
    }

    @Test("plaintext but corrupt payload → retry decode_failed")
    func plaintextCorruptPayload() async {
        let (ingress, _, _, _, _) = Self.makeIngress()
        let item = Self.sampleItem(kind: .plaintext, payload: Data([0xFF, 0xFE]))
        let reply = await ingress.ingest(item: item)
        #expect(reply.success == false)
        #expect(reply.reasonCode == "decode_failed")
    }

    @Test("schemaVersion mismatch → retry schema_mismatch")
    func schemaMismatch() async {
        let (ingress, _, _, _, _) = Self.makeIngress()
        let item = AgentMailboxItem(
            recordName: "REC",
            createdAt: Date(),
            sourceDeviceId: UUID(),
            payloadKind: .plaintext,
            payloadData: Data(),
            schemaVersion: 99
        )
        let reply = await ingress.ingest(item: item)
        #expect(reply.success == false)
        #expect(reply.reasonCode == "schema_mismatch")
    }

    @Test("handshake pair_init via agent path writes a plaintext reply record back to gateway")
    func handshakeReplyTraversesGateway() async throws {
        // Drive a real pair_init through the ingress; the router will
        // produce a `PairingCompleteAck` (plaintext) that must land
        // in `gateway.save(...)` so the iPhone can finish pairing.
        let macId = UUID()
        let gateway = RecordingGateway()
        let (ingress, _, _, _, pairingService) = Self.makeIngress(
            gateway: gateway,
            macDeviceId: macId
        )
        let invitation = await pairingService.beginPairing()
        let peer = DeviceIdentity.generate()
        let challenge = PairingService.challenge(
            token: invitation.token,
            devicePublicKey: peer.publicKeyData
        )
        let signature = try peer.sign(challenge)
        let request = PairingChallengeResponse(
            token: invitation.token,
            devicePublicKey: peer.publicKeyData,
            nickname: "iPhone",
            signature: signature,
            supportedCodecs: [.json],
            kemPublicKey: peer.kemPublicKeyData
        )
        let payload = try JSONRemoteCodec().encode(request)
        let envelope = Envelope(version: ProtocolVersion.current, kind: .pairInit, payload: payload)
        let envelopeBytes = try JSONEncoder().encode(envelope)
        let item = AgentMailboxItem(
            recordName: "REC-PAIR",
            createdAt: Date(),
            sourceDeviceId: DeviceIdentity.deriveDeviceId(from: peer.publicKeyData),
            payloadKind: .plaintext,
            payloadData: envelopeBytes
        )
        let reply = await ingress.ingest(item: item)
        #expect(reply.success == true)
        let saved = await gateway.snapshot()
        #expect(saved.count >= 1, "router pair_complete reply must reach gateway.save")
        // First saved record carries the plaintext PairingCompleteAck
        // back to the iPhone. Source/target id assertions verify the
        // agent's domain wiring.
        let first = try #require(saved.first)
        #expect(first.sourceDeviceId == macId)
        #expect(first.targetDeviceId == DeviceIdentity.deriveDeviceId(from: peer.publicKeyData))
        if case .plaintext = first.payload {
            // ok
        } else {
            Issue.record("handshake reply must be plaintext, got \(first.payload)")
        }
    }

    @Test("cipher decode failure → retry decode_failed")
    func cipherDecodeFailure() async {
        let (ingress, _, _, _, _) = Self.makeIngress()
        let item = Self.sampleItem(kind: .cipher, payload: Data([0x00, 0x01]))
        let reply = await ingress.ingest(item: item)
        #expect(reply.success == false)
        #expect(reply.reasonCode == "decode_failed")
    }
}
#endif
