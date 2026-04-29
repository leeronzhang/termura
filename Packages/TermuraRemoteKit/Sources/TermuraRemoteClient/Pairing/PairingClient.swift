import Foundation
import TermuraRemoteProtocol

public struct PairingClient: Sendable {
    public init() {}

    public func makeResponse(
        invitationToken: String,
        identity: DeviceIdentity,
        nickname: String,
        supportedCodecs: [CodecKind] = [.json]
    ) throws -> PairingChallengeResponse {
        let challenge = Self.challenge(token: invitationToken, devicePublicKey: identity.publicKeyData)
        let signature = try identity.sign(challenge)
        return PairingChallengeResponse(
            token: invitationToken,
            devicePublicKey: identity.publicKeyData,
            nickname: nickname,
            signature: signature,
            supportedCodecs: supportedCodecs,
            // PR7 — share the iOS X25519 KEM public key so the Mac can
            // derive the symmetric pair key independently. The iOS side
            // derives its own copy from `invitation.kemPublicKey` plus
            // the local KEM private key.
            kemPublicKey: identity.kemPublicKeyData
        )
    }

    public static func challenge(token: String, devicePublicKey: Data) -> Data {
        Data(token.utf8) + devicePublicKey
    }
}
