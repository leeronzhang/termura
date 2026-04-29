import Foundation
import MessagePack

/// `RemoteCodec` implementation backed by Flight-School's MessagePack encoder.
/// Negotiated via the pairing handshake; only used after both peers have
/// declared support and `PairingCompleteAck.negotiatedCodec == .messagepack`.
///
/// Stateless wrt configuration — every call constructs a fresh encoder /
/// decoder so the codec value remains `Sendable` despite Flight-School's
/// reference-typed encoder. The constructor cost is negligible (a couple of
/// allocations); offsetting that against avoiding `@unchecked Sendable` on a
/// security-adjacent type is the right trade.
public struct MessagePackRemoteCodec: RemoteCodec {
    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try MessagePackEncoder().encode(value)
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try MessagePackDecoder().decode(type, from: data)
    }
}
