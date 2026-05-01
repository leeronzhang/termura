import Foundation

/// Sent by an already-paired client on a fresh transport channel to
/// resume an authenticated session without consuming a new invitation.
/// The signature proves the client still controls the Ed25519 private
/// key the server registered at initial pair time; the timestamp + nonce
/// give anti-replay so a stolen rejoin payload can't be reused later.
public struct RejoinRequest: Sendable, Codable, Equatable {
    public let pairedDeviceId: UUID
    public let nonce: Data
    public let timestamp: Date
    /// Ed25519 signature over `RejoinRequest.signedBytes(...)` using the
    /// device's signing key — the same key persisted on Mac at initial
    /// `pairInit` (looked up from the paired-device store).
    public let signature: Data
    /// Codecs the client is willing to speak after rejoin. Server picks
    /// one and echoes it back in `RejoinAck.negotiatedCodec` so both
    /// peers switch to `.active(negotiatedCodec)` together — same
    /// contract as the initial `PairingCompleteAck` codec hop.
    public let supportedCodecs: [CodecKind]

    public init(
        pairedDeviceId: UUID,
        nonce: Data,
        timestamp: Date,
        signature: Data,
        supportedCodecs: [CodecKind]
    ) {
        self.pairedDeviceId = pairedDeviceId
        self.nonce = nonce
        self.timestamp = timestamp
        self.signature = signature
        self.supportedCodecs = supportedCodecs
    }

    /// Stable canonical bytes that both peers sign / verify. Layout:
    ///
    ///     [16 bytes pairedDeviceId UUID]
    ///     [N bytes nonce]
    ///     [8 bytes timestamp millis since epoch, big-endian Int64]
    ///
    /// Avoids string formatting (no locale / timezone surprises) and
    /// keeps the field order matched to the struct so callers can't
    /// accidentally reorder.
    public static func signedBytes(
        pairedDeviceId: UUID,
        nonce: Data,
        timestamp: Date
    ) -> Data {
        var bytes = Data()
        let id = pairedDeviceId.uuid
        let idBytes: [UInt8] = [
            id.0, id.1, id.2, id.3, id.4, id.5, id.6, id.7,
            id.8, id.9, id.10, id.11, id.12, id.13, id.14, id.15
        ]
        bytes.append(contentsOf: idBytes)
        bytes.append(nonce)
        let millis = Int64((timestamp.timeIntervalSince1970 * 1000).rounded())
        withUnsafeBytes(of: millis.bigEndian) { bytes.append(contentsOf: $0) }
        return bytes
    }

    private enum CodingKeys: String, CodingKey {
        case pairedDeviceId, nonce, timestamp, signature, supportedCodecs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pairedDeviceId = try container.decode(UUID.self, forKey: .pairedDeviceId)
        nonce = try container.decode(Data.self, forKey: .nonce)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        signature = try container.decode(Data.self, forKey: .signature)
        supportedCodecs = try container.decodeIfPresent(
            [CodecKind].self,
            forKey: .supportedCodecs
        ) ?? [.json]
    }
}

/// Server's reply to a successful `RejoinRequest`. Carries the codec
/// both peers must use for subsequent business envelopes — same
/// negotiation point as `PairingCompleteAck.negotiatedCodec`.
public struct RejoinAck: Sendable, Codable, Equatable {
    public let pairedDeviceId: UUID
    public let negotiatedCodec: CodecKind

    public init(pairedDeviceId: UUID, negotiatedCodec: CodecKind) {
        self.pairedDeviceId = pairedDeviceId
        self.negotiatedCodec = negotiatedCodec
    }

    private enum CodingKeys: String, CodingKey {
        case pairedDeviceId, negotiatedCodec
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pairedDeviceId = try container.decode(UUID.self, forKey: .pairedDeviceId)
        negotiatedCodec = try container.decodeIfPresent(
            CodecKind.self,
            forKey: .negotiatedCodec
        ) ?? .json
    }
}

/// Maximum age tolerated for a `RejoinRequest.timestamp` relative to
/// the server's clock. Beyond this window the server rejects with
/// `RemoteError.unauthorized` so a stolen / replayed rejoin from an
/// older session can't authenticate a fresh channel. 60s gives clock
/// drift slack while keeping the replay window small.
public enum RejoinPolicy {
    public static let timestampSkewTolerance: TimeInterval = 60
}
