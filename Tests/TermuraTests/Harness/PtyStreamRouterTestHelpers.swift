import Foundation
@testable import Termura
import TermuraRemoteProtocol
@testable import TermuraRemoteServer

/// Test-doubles + factory helpers shared by
/// `RemoteEnvelopeRouterPtyStreamTests` so the test file can stay
/// under the file-length budget without losing coverage. Kept
/// `internal` (not nested) so a single helper file serves any future
/// W4/W5 router tests on the same surface.

actor PtyStreamRecordingReplyChannel: ReplyChannel {
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

/// Adapter stub that lets each test prepare:
/// - `nextSubscription` — what `subscribePty` returns for the one session
///   it knows about (defaults to `nil` so unknown-session is the easy
///   default).
/// - `unsubscribeCalls` — captured `(sessionId, subscriptionId)` pairs
///   so tests can assert the router released the upstream tap.
actor PtyStreamStubAdapter: RemoteSessionsAdapter {
    let knownSessionId: UUID
    var nextSubscription: PtyByteTap.Subscription?
    private(set) var unsubscribeCalls: [(UUID, UUID)] = []
    private(set) var checkpointCalls: [(UUID, UInt64)] = []

    init(knownSessionId: UUID) {
        self.knownSessionId = knownSessionId
    }

    func setNextSubscription(_ sub: PtyByteTap.Subscription?) {
        nextSubscription = sub
    }

    nonisolated func listSessions() async -> [RemoteSessionInfo] {
        await [RemoteSessionInfo(id: knownSessionId, title: "stub",
                                 workingDirectory: nil,
                                 lastActivityAt: Date(timeIntervalSince1970: 0))]
    }

    nonisolated func executeCommand(line _: String, sessionId _: UUID) async throws -> CommandRunResult {
        CommandRunResult(stdout: "ok", exitCode: 0)
    }

    func subscribePty(sessionId: UUID) async -> PtyByteTap.Subscription? {
        guard sessionId == knownSessionId else { return nil }
        let sub = nextSubscription
        nextSubscription = nil
        return sub
    }

    func unsubscribePty(sessionId: UUID, subscriptionId: UUID) async {
        unsubscribeCalls.append((sessionId, subscriptionId))
    }

    func currentCheckpoint(sessionId: UUID, seq: UInt64) async -> PtyStreamCheckpoint? {
        checkpointCalls.append((sessionId, seq))
        return nil
    }
}

enum PtyStreamRouterFactory {
    static func makeRouter(adapter: any RemoteSessionsAdapter) -> RemoteEnvelopeRouter {
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
            codec: JSONRemoteCodec()
        )
    }

    static func subscribeEnvelope(
        sessionId: UUID,
        resumeFromSeq: UInt64? = nil
    ) throws -> Envelope {
        let codec = JSONRemoteCodec()
        let request = PtyStreamSubscribeRequest(sessionId: sessionId, resumeFromSeq: resumeFromSeq)
        let payload = try codec.encode(request)
        return Envelope(version: ProtocolVersion.current, kind: .ptyStreamSubscribe, payload: payload)
    }

    static func unsubscribeEnvelope(sessionId: UUID?) throws -> Envelope {
        let codec = JSONRemoteCodec()
        let request = PtyStreamUnsubscribeRequest(sessionId: sessionId)
        let payload = try codec.encode(request)
        return Envelope(version: ProtocolVersion.current, kind: .ptyStreamUnsubscribe, payload: payload)
    }
}
