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
