#if HARNESS_ENABLED
import Foundation
@testable import Termura
import TermuraRemoteProtocol
@testable import TermuraRemoteServer
import Testing

/// PR8 §3.6 / §8 — exercises `RemoteEnvelopeRouter.primeAuthenticatedChannel`
/// from the outside through observable side-effects. The router's
/// per-channel maps are private, so each test drives the router
/// through `handle(envelope:replyChannel:)` and asserts on the
/// reply envelope, the audit log, or the codec the router used to
/// decode the request.
///
/// Test-doubles + factory helpers
/// (`RouterPrimeRecordingReplyChannel`, `RouterPrimeStubSessionsAdapter`,
/// `RouterPrimeRecordingActivator`, `RouterPrimeFactory`) live in
/// `RouterPrimeTestHelpers.swift` so this file stays under the
/// file-length / type-body / nesting budgets.
@Suite("RemoteEnvelopeRouter.primeAuthenticatedChannel")
struct RouterPrimeAuthenticatedChannelTests {
    @Test("primed channel accepts kinds that require authentication")
    func primedChannelAcceptsAuthenticatedKinds() async {
        let deviceId = UUID()
        let router = RouterPrimeFactory.makeRouter(
            seededPairedDevices: [RouterPrimeFactory.activePairedDevice(id: deviceId)]
        )
        let channel = RouterPrimeRecordingReplyChannel()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: deviceId,
            negotiatedCodec: .json
        )
        await router.handle(
            envelope: RouterPrimeFactory.encodeSessionListRequest(),
            replyChannel: channel
        )
        let replies = await channel.snapshot()
        #expect(replies.count == 1)
        #expect(replies.first?.kind == .sessionList)
    }

    @Test("unprimed channel still rejects authenticated kinds")
    func unprimedChannelRejectsAuthenticatedKinds() async {
        let router = RouterPrimeFactory.makeRouter()
        let channel = RouterPrimeRecordingReplyChannel()
        await router.handle(
            envelope: RouterPrimeFactory.encodeSessionListRequest(),
            replyChannel: channel
        )
        let replies = await channel.snapshot()
        #expect(replies.count == 1)
        #expect(replies.first?.kind == .error)
    }

    @Test("primed channel decodes business envelopes with the agreed codec")
    func primedChannelUsesNegotiatedCodec() async throws {
        let messagepack = MessagePackRemoteCodec()
        let deviceId = UUID()
        let router = RouterPrimeFactory.makeRouter(
            seededPairedDevices: [RouterPrimeFactory.activePairedDevice(id: deviceId)]
        )
        let channel = RouterPrimeRecordingReplyChannel()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: deviceId,
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
        let deviceId = UUID()
        let router = RouterPrimeFactory.makeRouter(
            seededPairedDevices: [RouterPrimeFactory.activePairedDevice(id: deviceId)]
        )
        let channel = RouterPrimeRecordingReplyChannel()
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
            envelope: RouterPrimeFactory.encodeSessionListRequest(),
            replyChannel: channel
        )
        let replies = await channel.snapshot()
        #expect(replies.first?.kind == .sessionList)
    }

    @Test("pairComplete activator receives cloudSourceDeviceId, not pairedDeviceId")
    func pairCompleteActivatorReceivesCloudSourceDeviceId() async throws {
        // Recorder captures whatever the router hands to the activator.
        // The captured `sourceDeviceId` must be `cloudSourceDeviceId`,
        // not the randomly-generated paired-device id.
        let recorder = RouterPrimeActivatorRecorder()
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
            adapter: RouterPrimeStubSessionsAdapter(sessionId: UUID()),
            pairingService: pairingService,
            policy: DangerousCommandPolicy(),
            snapshotPublisher: snapshotPublisher,
            codec: JSONRemoteCodec(),
            cloudKitChannelActivator: RouterPrimeRecordingActivator(recorder: recorder)
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
        let channel = RouterPrimeRecordingReplyChannel()
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
        let firstDeviceId = UUID()
        let secondDeviceId = UUID()
        let router = RouterPrimeFactory.makeRouter(
            adapter: RouterPrimeStubSessionsAdapter(sessionId: sessionId),
            auditLog: auditLog,
            seededPairedDevices: [
                RouterPrimeFactory.activePairedDevice(id: firstDeviceId),
                RouterPrimeFactory.activePairedDevice(id: secondDeviceId)
            ]
        )
        let channel = RouterPrimeRecordingReplyChannel()
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
            .filter { if case .dispatched = $0.outcome { true } else { false } }
            .map(\.deviceId)
        #expect(dispatchedDeviceIds == [firstDeviceId])
        #expect(!dispatchedDeviceIds.contains(secondDeviceId))
    }
}
#endif
