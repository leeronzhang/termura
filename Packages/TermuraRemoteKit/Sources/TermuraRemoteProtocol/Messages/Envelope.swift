import Foundation

public struct Envelope: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case pairInit = "pair_init"
        case pairComplete = "pair_complete"
        /// Lightweight session-resumption sent by an already-paired client on
        /// a fresh transport channel. Allowed during handshake; the server
        /// validates a signature over a stable byte string built from the
        /// persisted paired-device id + a fresh nonce + a timestamp, then
        /// flips the channel to `.authenticated` without a new invitation.
        case rejoin
        case rejoinAck = "rejoin_ack"
        case cmdExec = "cmd_exec"
        case cmdCancel = "cmd_cancel"
        case cmdAck = "cmd_ack"
        case cmdConfirmRequest = "cmd_confirm_request"
        case cmdConfirmResponse = "cmd_confirm_response"
        case snapshotChunk = "snapshot_chunk"
        case snapshotAttachmentRef = "snapshot_attachment_ref"
        case snapshotEnd = "snapshot_end"
        case sessionListRequest = "session_list_request"
        case sessionList = "session_list"
        /// Client → server: subscribe to a session's live screen frames so
        /// the client can render the Mac terminal without depending on
        /// command request/response (works for REPLs like Claude Code that
        /// don't emit OSC 133;D shell-integration markers).
        case screenSubscribe = "screen_subscribe"
        /// Client → server: cancel a prior `.screenSubscribe`. Idempotent.
        case screenUnsubscribe = "screen_unsubscribe"
        /// Server → client: a single visible-region snapshot for one
        /// subscribed session. Pushed by a per-subscription pulse on the
        /// server; coalesced when the rendered text hasn't changed.
        case screenFrame = "screen_frame"
        /// Client → server: subscribe to a session's raw PTY byte stream
        /// so the client can run its own vt engine locally and reflow
        /// to its own viewport (iOS columns differ from Mac PTY columns).
        /// Available when peer reports `PeerCapabilities.ptyStream`
        /// (protocol >= 1.1).
        case ptyStreamSubscribe = "pty_stream_subscribe"
        /// Client → server: cancel a prior `.ptyStreamSubscribe`. Idempotent.
        case ptyStreamUnsubscribe = "pty_stream_unsubscribe"
        /// Server → client: a coalesced batch of raw PTY bytes for one
        /// subscribed session. Carries a monotonic `seq` per channel/session
        /// so the client can detect gaps and resume.
        case ptyStreamChunk = "pty_stream_chunk"
        /// Server → client: full-viewport keyframe for cold-restore /
        /// resync after a chunk-seq gap. Built from the same data shape
        /// `ScreenFramePayload` carries plus cursor position.
        case ptyStreamCheckpoint = "pty_stream_checkpoint"
        /// Client → server: forward an iOS-driven local reflow to the Mac
        /// PTY so the upstream shell / REPL re-emits its own output at
        /// the new column count. Fire-and-forget — the server may reject
        /// (Mac user is currently active, see A2 guard) without an
        /// envelope reply. Available when peer reports
        /// `PeerCapabilities.ptyResize` (protocol >= 1.2).
        case ptyResize = "pty_resize"
        /// Client → server: subscribe to a session's agent conversation
        /// event stream (Mac parses Claude Code transcript JSONL into
        /// structured `AgentEvent` envelopes; iOS renders with native
        /// SwiftUI chat UI instead of vt terminal emulation).
        /// Available when peer reports `PeerCapabilities.agentEvents`
        /// (protocol >= 1.3).
        case agentEventSubscribe = "agent_event_subscribe"
        /// Client → server: cancel a prior `.agentEventSubscribe`.
        /// Idempotent.
        case agentEventUnsubscribe = "agent_event_unsubscribe"
        /// Server → client: a single agent conversation event.
        case agentEvent = "agent_event"
        /// Server → client: cold-start basis (most recent N events)
        /// shipped on subscribe-success when the client has no
        /// `sinceEventId` or its cursor fell outside retention.
        case agentEventCheckpoint = "agent_event_checkpoint"
        case ping
        case pong
        case error
    }

    public let version: ProtocolVersion
    public let id: UUID
    public let kind: Kind
    public let payload: Data
    public let createdAt: Date

    public init(
        version: ProtocolVersion = .current,
        id: UUID = UUID(),
        kind: Kind,
        payload: Data,
        createdAt: Date = Date()
    ) {
        self.version = version
        self.id = id
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
    }
}

public extension Envelope {
    static func encode(
        _ inner: some Encodable,
        kind: Kind,
        codec: any RemoteCodec,
        version: ProtocolVersion = .current,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) throws -> Envelope {
        let payload = try codec.encode(inner)
        return Envelope(version: version, id: id, kind: kind, payload: payload, createdAt: createdAt)
    }

    func decode<T: Decodable>(_ type: T.Type, codec: any RemoteCodec) throws -> T {
        try codec.decode(type, from: payload)
    }
}
