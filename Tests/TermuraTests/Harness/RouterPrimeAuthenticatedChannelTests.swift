#if HARNESS_ENABLED
import Foundation
@testable import Termura
import Testing
import TermuraRemoteProtocol
@testable import TermuraRemoteServer

/// PR8 §3.6 / §8 — exercises `RemoteEnvelopeRouter.primeAuthenticatedChannel`
/// from the outside through observable side-effects. The router's
/// per-channel `channels` / `phases` maps are private, so each test
/// drives the router through `handle(envelope:replyChannel:)` and
/// asserts on the reply envelope, the audit log, or the codec the
/// router used to decode the request.
@Suite("RemoteEnvelopeRouter.primeAuthenticatedChannel")
struct RouterPrimeAuthenticatedChannelTests {
    private actor RecordingReplyChannel: ReplyChannel {
        nonisolated let channelId: UUID
        private(set) var sent: [Envelope] = []
        private(set) var closed = false

        init(channelId: UUID = UUID()) {
            self.channelId = channelId
        }

        func send(_ envelope: Envelope) async throws {
            sent.append(envelope)
        }

        func close() async {
            closed = true
        }

        func snapshot() -> [Envelope] { sent }
    }

    private actor ActivatorRecorder {
        struct Call: Sendable {
            let source: UUID
            let pairingId: UUID
        }

        private(set) var captured: [Call] = []

        func record(source: UUID, pairingId: UUID) {
            captured.append(Call(source: source, pairingId: pairingId))
        }

        func calls() -> [Call] { captured }
    }

    private struct StubSessionsAdapter: RemoteSessionsAdapter {
        let sessionId: UUID

        func listSessions() async -> [RemoteSessionInfo] {
            [RemoteSessionInfo(
                id: sessionId,
                title: "stub",
                workingDirectory: nil,
                lastActivityAt: Date(timeIntervalSince1970: 1_000)
            )]
        }

        func executeCommand(line _: String, sessionId _: UUID) async throws -> CommandRunResult {
            CommandRunResult(stdout: "ok", exitCode: 0)
        }
    }

    private static func makeRouter(
        codec: any RemoteCodec = JSONRemoteCodec(),
        adapter: any RemoteSessionsAdapter = StubSessionsAdapter(sessionId: UUID()),
        auditLog: InMemoryAuditLogStore = InMemoryAuditLogStore()
    ) -> RemoteEnvelopeRouter {
        let identity = DeviceIdentity.generate()
        let issuer = PairingTokenIssuer(
            lifetime: 300,
            randomBytes: { count in Data(repeating: 0xAA, count: count) }
        )
        let pairingService = PairingService(
            identity: identity,
            tokenIssuer: issuer,
            store: InMemoryPairedDeviceStore(),
            serviceName: "test-mac"
        )
        let snapshotPublisher = SnapshotPublisher(attachmentStore: NullAttachmentStore())
        return RemoteEnvelopeRouter(
            adapter: adapter,
            pairingService: pairingService,
            policy: DangerousCommandPolicy(),
            snapshotPublisher: snapshotPublisher,
            codec: codec,
            auditLog: auditLog
        )
    }

    private static func encodeSessionListRequest(
        codec: any RemoteCodec
    ) -> Envelope {
        Envelope(version: ProtocolVersion.current, kind: .sessionListRequest, payload: Data())
    }

    @Test("primed channel accepts kinds that require authentication")
    func primedChannelAcceptsAuthenticatedKinds() async {
        let router = Self.makeRouter()
        let channel = RecordingReplyChannel()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: UUID(),
            negotiatedCodec: .json
        )
        await router.handle(
            envelope: Self.encodeSessionListRequest(codec: JSONRemoteCodec()),
            replyChannel: channel
        )
        let replies = await channel.snapshot()
        #expect(replies.count == 1)
        #expect(replies.first?.kind == .sessionList)
    }

    @Test("unprimed channel still rejects authenticated kinds")
    func unprimedChannelRejectsAuthenticatedKinds() async {
        let router = Self.makeRouter()
        let channel = RecordingReplyChannel()
        await router.handle(
            envelope: Self.encodeSessionListRequest(codec: JSONRemoteCodec()),
            replyChannel: channel
        )
        let replies = await channel.snapshot()
        #expect(replies.count == 1)
        #expect(replies.first?.kind == .error)
    }

    @Test("primed channel decodes business envelopes with the agreed codec")
    func primedChannelUsesNegotiatedCodec() async throws {
        let messagepack = MessagePackRemoteCodec()
        let router = Self.makeRouter()
        let channel = RecordingReplyChannel()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: UUID(),
            negotiatedCodec: .messagepack
        )
        let command = RemoteCommand(
            sessionId: UUID(),
            line: "echo hi",
            clientPreCheck: .safe
        )
        let payload = try messagepack.encode(command)
        let envelope = Envelope(version: ProtocolVersion.current, kind: .cmdExec, payload: payload)
        await router.handle(envelope: envelope, replyChannel: channel)
        // Replies: cmdAck + snapshotChunk. If the router had decoded
        // with the handshake (JSON) codec, decode would have failed
        // and the reply would be a single .error envelope.
        let replies = await channel.snapshot()
        #expect(replies.contains(where: { $0.kind == .cmdAck }))
        #expect(replies.contains(where: { $0.kind == .snapshotChunk }))
        #expect(replies.allSatisfy { $0.kind != .error })
    }

    @Test("repeat prime with same params is a no-op")
    func repeatPrimeWithSameParamsIsNoOp() async {
        let router = Self.makeRouter()
        let channel = RecordingReplyChannel()
        let deviceId = UUID()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: deviceId,
            negotiatedCodec: .json
        )
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: deviceId,
            negotiatedCodec: .json
        )
        await router.handle(
            envelope: Self.encodeSessionListRequest(codec: JSONRemoteCodec()),
            replyChannel: channel
        )
        let replies = await channel.snapshot()
        #expect(replies.first?.kind == .sessionList)
    }

    @Test("pairComplete activator receives cloudSourceDeviceId, not pairedDeviceId")
    func pairCompleteActivatorReceivesCloudSourceDeviceId() async throws {
        // Recorder captures whatever the router hands to the activator.
        // The captured `sourceDeviceId` is the value
        // `CloudKitTransport.setActivePairingId(_:forSourceDeviceId:)`
        // would receive — must be `cloudSourceDeviceId`, not the
        // randomly-generated paired-device id.
        let recorder = ActivatorRecorder()
        let identity = DeviceIdentity.generate()
        let issuer = PairingTokenIssuer(
            lifetime: 300,
            randomBytes: { count in Data(repeating: 0xAA, count: count) }
        )
        let pairingService = PairingService(
            identity: identity,
            tokenIssuer: issuer,
            store: InMemoryPairedDeviceStore(),
            serviceName: "test-mac"
        )
        let snapshotPublisher = SnapshotPublisher(attachmentStore: NullAttachmentStore())
        let router = RemoteEnvelopeRouter(
            adapter: StubSessionsAdapter(sessionId: UUID()),
            pairingService: pairingService,
            policy: DangerousCommandPolicy(),
            snapshotPublisher: snapshotPublisher,
            codec: JSONRemoteCodec(),
            cloudKitPairingActivator: { source, pairingId in
                await recorder.record(source: source, pairingId: pairingId)
            }
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
        let channel = RecordingReplyChannel()
        await router.handle(envelope: envelope, replyChannel: channel)

        let calls = await recorder.calls()
        #expect(calls.count == 1)
        let captured = try #require(calls.first)
        let expectedCloudId = DeviceIdentity.deriveDeviceId(from: peer.publicKeyData)
        #expect(captured.source == expectedCloudId)
        // Defence-in-depth: the activator must NOT have been called
        // with the paired-device id. The two domains overlap by
        // probability 2^-128, so a strict inequality is meaningful.
        let pairedDevices = try await pairingService.listPairedDevices()
        let pairedDeviceId = try #require(pairedDevices.first { $0.publicKey == peer.publicKeyData }).id
        #expect(captured.source != pairedDeviceId)
    }

    @Test("repeat prime with different deviceId keeps the first deviceId in audit log")
    func repeatPrimeKeepsFirstDeviceIdInAuditLog() async throws {
        let auditLog = InMemoryAuditLogStore()
        let sessionId = UUID()
        let router = Self.makeRouter(
            adapter: StubSessionsAdapter(sessionId: sessionId),
            auditLog: auditLog
        )
        let channel = RecordingReplyChannel()
        let firstDeviceId = UUID()
        let secondDeviceId = UUID()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: firstDeviceId,
            negotiatedCodec: .json
        )
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: secondDeviceId,
            negotiatedCodec: .json
        )
        let codec = JSONRemoteCodec()
        let command = RemoteCommand(
            sessionId: sessionId,
            line: "echo safe",
            clientPreCheck: .safe
        )
        let payload = try codec.encode(command)
        let envelope = Envelope(version: ProtocolVersion.current, kind: .cmdExec, payload: payload)
        await router.handle(envelope: envelope, replyChannel: channel)
        let entries = await auditLog.recent(limit: 10)
        let dispatchedDeviceIds = entries
            .filter { if case .dispatched = $0.outcome { return true } else { return false } }
            .map(\.deviceId)
        #expect(dispatchedDeviceIds == [firstDeviceId])
        #expect(!dispatchedDeviceIds.contains(secondDeviceId))
    }
}
#endif
