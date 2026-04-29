import Foundation

/// Transport-neutral representation of a single envelope persisted in
/// the CloudKit mailbox. Platform gateways translate to/from `CKRecord`
/// using `CloudKitSchema.Field.*` keys.
///
/// PR7 — the payload now has two mutually-exclusive shapes:
///
///   * `.cipher(CipherBlob)` — the business-phase default. The envelope
///     bytes are sealed with the per-pair `PairKey` so CloudKit only
///     ever sees ciphertext + routing metadata.
///   * `.plaintext(Envelope)` — pair-handshake bootstrap path. Used
///     while the two peers are still establishing the symmetric key on
///     a CloudKit-mode initial pair (`pair_init` / `pair_complete` /
///     `error` / `ping` / `pong`). Once `PairingCompleteAck` lands,
///     business envelopes flip to the cipher branch.
public struct CloudKitEnvelopeRecord: Sendable, Equatable, Identifiable {
    public enum Payload: Sendable, Equatable {
        case cipher(CipherBlob)
        case plaintext(Envelope)
    }

    public let id: String
    public let payload: Payload
    public let targetDeviceId: UUID
    public let sourceDeviceId: UUID
    public let createdAt: Date
    public let schemaVersion: Int

    public init(
        id: String,
        payload: Payload,
        targetDeviceId: UUID,
        sourceDeviceId: UUID,
        createdAt: Date,
        schemaVersion: Int = CloudKitSchema.currentSchemaVersion
    ) {
        self.id = id
        self.payload = payload
        self.targetDeviceId = targetDeviceId
        self.sourceDeviceId = sourceDeviceId
        self.createdAt = createdAt
        self.schemaVersion = schemaVersion
    }
}
