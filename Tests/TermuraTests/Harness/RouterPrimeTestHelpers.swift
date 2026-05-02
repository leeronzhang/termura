// Test-doubles + factory helpers shared by
// `RouterPrimeAuthenticatedChannelTests`. Pulled into their own file
// so the test suite stays under the file-length / type-body /
// nesting budgets.

#if HARNESS_ENABLED
import Foundation
@testable import Termura
import TermuraRemoteProtocol
@testable import TermuraRemoteServer

actor RouterPrimeRecordingReplyChannel: ReplyChannel {
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

/// Captured activator call. File-scope to avoid the
/// SwiftLint nesting>1 violation triggered when this lived inside
/// `ActivatorRecorder`.
struct RouterPrimeActivatorCall: Sendable {
    let source: UUID
    let pairingId: UUID
}

actor RouterPrimeActivatorRecorder {
    private(set) var captured: [RouterPrimeActivatorCall] = []

    func record(source: UUID, pairingId: UUID) {
        captured.append(RouterPrimeActivatorCall(source: source, pairingId: pairingId))
    }

    func calls() -> [RouterPrimeActivatorCall] { captured }
}

/// `CloudKitChannelActivator` (Wave 5) is a protocol now, not a
/// closure. Forwards every call to the test's recorder actor so
/// existing assertions on `recorder.calls()` keep working.
struct RouterPrimeRecordingActivator: CloudKitChannelActivator {
    let recorder: RouterPrimeActivatorRecorder

    func activate(pairingId: UUID, forSourceDeviceId source: UUID) async {
        await recorder.record(source: source, pairingId: pairingId)
    }
}

struct RouterPrimeStubSessionsAdapter: RemoteSessionsAdapter {
    let sessionId: UUID

    func listSessions() async -> [RemoteSessionInfo] {
        [RemoteSessionInfo(
            id: sessionId,
            title: "stub",
            workingDirectory: nil,
            lastActivityAt: Date(timeIntervalSince1970: 1000)
        )]
    }

    func executeCommand(line _: String, sessionId _: UUID) async throws -> CommandRunResult {
        CommandRunResult(stdout: "ok", exitCode: 0)
    }
}

enum RouterPrimeFactory {
    /// Active `PairedDevice` for `deviceId` so the router's W4
    /// `requireActiveDevice` revoke check passes when prime is driven
    /// with a synthetic UUID.
    static func activePairedDevice(id: UUID) -> PairedDevice {
        PairedDevice(
            id: id,
            nickname: "test",
            publicKey: Data(repeating: 0xAB, count: 32),
            pairedAt: Date(timeIntervalSince1970: 0),
            revokedAt: nil
        )
    }

    static func makeRouter(
        codec: any RemoteCodec = JSONRemoteCodec(),
        adapter: any RemoteSessionsAdapter = RouterPrimeStubSessionsAdapter(sessionId: UUID()),
        auditLog: InMemoryAuditLogStore = InMemoryAuditLogStore(),
        seededPairedDevices: [PairedDevice] = []
    ) -> RemoteEnvelopeRouter {
        let identity = DeviceIdentity.generate()
        let issuer = PairingTokenIssuer(
            lifetime: 300,
            randomBytes: { count in Data(repeating: 0xAA, count: count) }
        )
        let pairingService = PairingService(
            identity: identity,
            tokenIssuer: issuer,
            store: InMemoryPairedDeviceStore(seed: seededPairedDevices),
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

    static func encodeSessionListRequest() -> Envelope {
        Envelope(version: ProtocolVersion.current, kind: .sessionListRequest, payload: Data())
    }
}
#endif
