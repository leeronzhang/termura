import Foundation

public struct Envelope: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case pairInit = "pair_init"
        case pairComplete = "pair_complete"
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
    static func encode<T: Encodable>(
        _ inner: T,
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
