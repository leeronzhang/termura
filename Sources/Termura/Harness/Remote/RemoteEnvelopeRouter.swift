// Routes incoming envelopes per connection. Tracks per-channel auth state plus
// per-channel pending dangerous commands. Pre-pair: only `pairInit` and `ping`
// pass; everything else returns `unauthorized`. After pair the channel can issue
// session/cmd kinds, but `cmd_exec` lines matching `DangerousCommandPolicy` are
// held until the channel returns a `cmd_confirm_response` with `approved=true`.
//
// The pairing flow lives in `+Pairing.swift`, the command kernel
// (cmd_exec / cmd_cancel / cmd_confirm_response / snapshot pack) lives
// in `+Command.swift`, the session-list broadcaster lives in
// `+Broadcast.swift`, the live-screen pulse in `+ScreenSubscribe.swift`,
// and the agent-bridge channel priming in `+ChannelPriming.swift`.
// All those extensions reach module-internal stored properties on this
// actor; the routing core below is the single dispatch surface.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter")

actor RemoteEnvelopeRouter: EnvelopeHandler {
    struct PendingCommand: Sendable {
        let command: RemoteCommand
        let channelId: UUID
        let reason: String
    }

    enum ChannelState: Sendable {
        case unauthenticated
        case authenticated(deviceId: UUID)
    }

    /// Module-internal so the same-module `+Broadcast` extension can pull
    /// the live session list (`adapter.listSessions()`) and subscribe to
    /// change pings (`adapter.sessionListChanges()`). Conceptually private
    /// to the router; no other type in the module references it.
    let adapter: any RemoteSessionsAdapter
    let pairingService: PairingService
    let policy: DangerousCommandPolicy
    /// Always-JSON codec used during the handshake phase, before the peer's
    /// `supportedCodecs` is known. Held alongside `messagepackCodec` so the
    /// router can switch as soon as `PairingCompleteAck` is sent.
    let handshakeCodec: any RemoteCodec
    let messagepackCodec: any RemoteCodec
    let snapshotPublisher: SnapshotPublisher
    let versionGate: VersionGate
    var channels: [UUID: ChannelState] = [:]
    var phases: [UUID: ConnectionPhase] = [:]
    /// Live reply handles for every authenticated channel. Populated when
    /// `handlePairInit` accepts a peer (or `primeAuthenticatedChannel`
    /// re-attaches an agent-woken channel) and dropped in `connectionClosed`.
    /// Used by `broadcastSessionList()` to fan out an unsolicited
    /// `sessionList` envelope whenever the host's session store changes.
    var replyChannels: [UUID: any ReplyChannel] = [:]
    /// Background task that consumes `adapter.sessionListChanges()` and
    /// triggers a fan-out broadcast on every emission. `nil` until
    /// `startBroadcasting()` runs and after `stopBroadcasting()`.
    var broadcastTask: Task<Void, Never>?
    /// Live-screen push subscriptions, keyed `channelId → sessionId → Task`.
    var screenSubscriptions: [UUID: [UUID: Task<Void, Never>]] = [:]
    /// Last-pushed `ScreenFramePayload.renderHash` per `(channelId, sessionId)`
    /// so the pulse skips identical frames.
    var screenLastHash: [UUID: [UUID: Int]] = [:]
    /// W3 — Live PTY-byte-stream push subscriptions + monotonic seq +
    /// W5 resume ring. Touched by `+PtyStream.swift` only.
    var ptyStreamSubscriptions: [UUID: [UUID: PtyStreamSubscriptionEntry]] = [:]
    var ptyStreamSeq: [UUID: [UUID: UInt64]] = [:]
    var ptyResumeBuffers: [UUID: [UUID: PtyResumeRing]] = [:]
    /// Wave 8 — agent-event subscriptions + per-session wire seq;
    /// touched by `+AgentEvents.swift` only.
    var agentEventSubscriptions: [UUID: [UUID: AgentEventSubscriptionEntry]] = [:]
    var agentEventSeq: [UUID: [UUID: UInt64]] = [:]
    var pending: [UUID: PendingCommand] = [:]
    /// In-flight execution tasks keyed by commandId. Populated when a command
    /// passes the policy gate and execution starts; removed when the task
    /// finishes. `cmd_cancel` cancels the task here.
    var inFlight: [UUID: InFlightEntry] = [:]

    struct InFlightEntry {
        let task: Task<Void, Never>
        let channelId: UUID
    }

    let auditLog: any AuditLogStore
    let clock: @Sendable () -> Date
    /// Wave 5 — activator the harness wires up to flip the CloudKit
    /// transport's per-peer reply channel from plaintext-bootstrap to
    /// encrypted mode after a successful pair / rejoin handshake.
    /// Pre-Wave-5 this was a closure of opaque shape; the
    /// `CloudKitChannelActivator` protocol gives the call site a
    /// self-documenting name and keeps the router decoupled from
    /// `CloudKitTransport`. LAN-only builds inject
    /// `NullCloudKitChannelActivator()` so the call site is free of
    /// Optional handling.
    let cloudKitChannelActivator: any CloudKitChannelActivator

    init(
        adapter: any RemoteSessionsAdapter,
        pairingService: PairingService,
        policy: DangerousCommandPolicy,
        snapshotPublisher: SnapshotPublisher,
        codec: any RemoteCodec,
        auditLog: any AuditLogStore = InMemoryAuditLogStore(),
        versionGate: VersionGate = VersionGate(),
        clock: @escaping @Sendable () -> Date = { Date() },
        cloudKitChannelActivator: any CloudKitChannelActivator = NullCloudKitChannelActivator()
    ) {
        self.adapter = adapter
        self.pairingService = pairingService
        self.policy = policy
        self.snapshotPublisher = snapshotPublisher
        handshakeCodec = codec
        messagepackCodec = MessagePackRemoteCodec()
        self.versionGate = versionGate
        self.auditLog = auditLog
        self.clock = clock
        self.cloudKitChannelActivator = cloudKitChannelActivator
    }

    func deviceId(for channelId: UUID) -> UUID? {
        if case let .authenticated(id) = channels[channelId, default: .unauthenticated] {
            return id
        }
        return nil
    }

    func recordAudit(
        deviceId: UUID?,
        command: RemoteCommand,
        verdict: SafetyVerdict,
        outcome: RemoteAuditOutcome
    ) async {
        guard let deviceId else { return }
        let entry = RemoteAuditEntry(
            timestamp: clock(),
            deviceId: deviceId,
            line: command.line,
            verdict: verdict,
            outcome: outcome
        )
        await auditLog.append(entry)
    }

    /// Returns the codec that should be used to encode/decode envelopes on
    /// `channelId`. Defaults to JSON until the channel transitions to active.
    func codec(for channelId: UUID) -> any RemoteCodec {
        let phase = phases[channelId, default: .handshake]
        switch phase {
        case .handshake:
            return handshakeCodec
        case let .active(kind):
            return kind == .messagepack ? messagepackCodec : handshakeCodec
        }
    }

    func handle(envelope: Envelope, replyChannel: any ReplyChannel) async {
        // Version gate runs first so incompatible peers never advance further.
        if let versionError = versionGate.check(envelope) {
            await replyError(
                versionError.code,
                message: versionError.message,
                origin: envelope,
                via: replyChannel
            )
            await replyChannel.close()
            return
        }

        // Handshake phase enforcement: any kind outside the allowed set is a
        // protocol violation and the connection is closed.
        let phase = phases[replyChannel.channelId, default: .handshake]
        if phase.isHandshake, !envelope.kind.isAllowedDuringHandshake {
            await replyError(
                .handshakeViolation,
                message: "Envelope kind \(envelope.kind.rawValue) not allowed before pairing completes",
                origin: envelope,
                via: replyChannel
            )
            await replyChannel.close()
            return
        }

        await dispatch(envelope: envelope, replyChannel: replyChannel)
    }

    /// Routes an envelope that has cleared `versionGate` and the handshake
    /// allow-list. Pulled out of `handle(...)` so the dispatch ladder can
    /// grow without inflating the public entry-point past its size budget.
    private func dispatch(envelope: Envelope, replyChannel: any ReplyChannel) async {
        switch envelope.kind {
        case .ping:
            await reply(kind: .pong, payload: Data(), origin: envelope, via: replyChannel)
        case .pairInit:
            await handlePairInit(envelope: envelope, replyChannel: replyChannel)
        case .rejoin:
            await handleRejoin(envelope: envelope, replyChannel: replyChannel)
        case .screenSubscribe:
            await handleScreenSubscribe(envelope: envelope, replyChannel: replyChannel)
        case .screenUnsubscribe:
            await handleScreenUnsubscribe(envelope: envelope, replyChannel: replyChannel)
        case .ptyStreamSubscribe, .ptyStreamUnsubscribe, .ptyResize,
             .agentEventSubscribe, .agentEventUnsubscribe:
            // All subscription-style envelopes share one fan-in so
            // this top-level dispatch stays under cyclomatic_complexity
            // 15. The fan-in re-splits them by kind into their
            // per-feature handlers.
            await dispatchSubscriptionEnvelope(envelope: envelope, replyChannel: replyChannel)
        case .sessionListRequest:
            guard await requireActiveDevice(envelope: envelope, replyChannel: replyChannel,
                                            unauthorizedMessage: "Pair before listing sessions") else { return }
            await replyWithSessionList(origin: envelope, via: replyChannel)
        case .cmdExec:
            guard await requireActiveDevice(envelope: envelope, replyChannel: replyChannel,
                                            unauthorizedMessage: "Pair before sending commands") else { return }
            await handleCommandExec(envelope: envelope, replyChannel: replyChannel)
        case .cmdConfirmResponse:
            guard await requireActiveDevice(envelope: envelope, replyChannel: replyChannel,
                                            unauthorizedMessage: "Pair before confirming") else { return }
            await handleConfirmResponse(envelope: envelope, replyChannel: replyChannel)
        case .cmdCancel:
            guard await requireActiveDevice(envelope: envelope, replyChannel: replyChannel,
                                            unauthorizedMessage: "Pair before cancelling") else { return }
            await handleCmdCancel(envelope: envelope, replyChannel: replyChannel)
        default:
            await replyError(
                .internalFailure,
                message: "Envelope kind \(envelope.kind.rawValue) not supported",
                origin: envelope,
                via: replyChannel
            )
        }
    }
}
