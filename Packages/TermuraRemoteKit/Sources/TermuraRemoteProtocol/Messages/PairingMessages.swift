import Foundation

public struct PairingInvitation: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public let token: String
    public let macPublicKey: Data
    public let serviceName: String
    public let expiresAt: Date
    /// Codecs the Mac (server) is willing to speak. Defaults to `[.json]` so
    /// envelopes encoded by older builds without this field decode safely.
    public let supportedCodecs: [CodecKind]
    /// PR7 — Mac's X25519 KEM public key. Combined with the iOS KEM
    /// private key plus `pairingNonce` to derive the symmetric pair key
    /// via HKDF. Empty for legacy Mac builds without the field.
    public let kemPublicKey: Data
    /// PR7 — 16-byte salt for the pair-key HKDF, generated fresh per
    /// invitation. Empty for legacy invitations.
    public let pairingNonce: Data
    /// PR7 — stable id under which both peers persist the derived
    /// `PairKey`. Mac picks this when issuing the invitation and echoes
    /// it back in `PairingCompleteAck` so iOS can fetch the same key
    /// without an extra round-trip.
    public let pairingId: UUID

    public init(
        schemaVersion: Int = 1,
        token: String,
        macPublicKey: Data,
        serviceName: String,
        expiresAt: Date,
        supportedCodecs: [CodecKind] = [.json],
        kemPublicKey: Data = Data(),
        pairingNonce: Data = Data(),
        pairingId: UUID = UUID()
    ) {
        self.schemaVersion = schemaVersion
        self.token = token
        self.macPublicKey = macPublicKey
        self.serviceName = serviceName
        self.expiresAt = expiresAt
        self.supportedCodecs = supportedCodecs
        self.kemPublicKey = kemPublicKey
        self.pairingNonce = pairingNonce
        self.pairingId = pairingId
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, token, macPublicKey, serviceName, expiresAt, supportedCodecs
        case kemPublicKey, pairingNonce, pairingId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        token = try container.decode(String.self, forKey: .token)
        macPublicKey = try container.decode(Data.self, forKey: .macPublicKey)
        serviceName = try container.decode(String.self, forKey: .serviceName)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        supportedCodecs = try container.decodeIfPresent([CodecKind].self, forKey: .supportedCodecs) ?? [.json]
        kemPublicKey = try container.decodeIfPresent(Data.self, forKey: .kemPublicKey) ?? Data()
        pairingNonce = try container.decodeIfPresent(Data.self, forKey: .pairingNonce) ?? Data()
        pairingId = try container.decodeIfPresent(UUID.self, forKey: .pairingId) ?? UUID()
    }
}

public struct PairingChallengeResponse: Sendable, Codable, Equatable {
    public let token: String
    public let devicePublicKey: Data
    public let nickname: String
    public let signature: Data
    /// Codecs the iPhone (client) is willing to speak. Defaults to `[.json]`
    /// for legacy clients.
    public let supportedCodecs: [CodecKind]
    /// PR7 — iOS's X25519 KEM public key. Mac combines it with its own
    /// KEM private key plus the invitation's `pairingNonce` to derive
    /// the same symmetric `PairKey` iOS computes locally. Empty for
    /// legacy iOS builds without the field.
    public let kemPublicKey: Data

    public init(
        token: String,
        devicePublicKey: Data,
        nickname: String,
        signature: Data,
        supportedCodecs: [CodecKind] = [.json],
        kemPublicKey: Data = Data()
    ) {
        self.token = token
        self.devicePublicKey = devicePublicKey
        self.nickname = nickname
        self.signature = signature
        self.supportedCodecs = supportedCodecs
        self.kemPublicKey = kemPublicKey
    }

    private enum CodingKeys: String, CodingKey {
        case token, devicePublicKey, nickname, signature, supportedCodecs, kemPublicKey
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        devicePublicKey = try container.decode(Data.self, forKey: .devicePublicKey)
        nickname = try container.decode(String.self, forKey: .nickname)
        signature = try container.decode(Data.self, forKey: .signature)
        supportedCodecs = try container.decodeIfPresent([CodecKind].self, forKey: .supportedCodecs) ?? [.json]
        kemPublicKey = try container.decodeIfPresent(Data.self, forKey: .kemPublicKey) ?? Data()
    }
}

public struct PairingCompleteAck: Sendable, Codable, Equatable {
    public let deviceId: UUID
    public let pairedAt: Date
    /// Codec selected by the server during pairing. Both peers must switch
    /// their connection state to `.active(negotiatedCodec)` after this ack
    /// crosses the wire.
    public let negotiatedCodec: CodecKind
    /// PR7 — id Mac persisted the derived `PairKey` under, echoed from
    /// the invitation so the iOS side can fetch the same key from its
    /// own `PairKeyStore` without re-running HKDF lookup.
    public let pairingId: UUID

    public init(
        deviceId: UUID,
        pairedAt: Date,
        negotiatedCodec: CodecKind = .json,
        pairingId: UUID = UUID()
    ) {
        self.deviceId = deviceId
        self.pairedAt = pairedAt
        self.negotiatedCodec = negotiatedCodec
        self.pairingId = pairingId
    }

    private enum CodingKeys: String, CodingKey {
        case deviceId, pairedAt, negotiatedCodec, pairingId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try container.decode(UUID.self, forKey: .deviceId)
        pairedAt = try container.decode(Date.self, forKey: .pairedAt)
        negotiatedCodec = try container.decodeIfPresent(CodecKind.self, forKey: .negotiatedCodec) ?? .json
        pairingId = try container.decodeIfPresent(UUID.self, forKey: .pairingId) ?? UUID()
    }
}
