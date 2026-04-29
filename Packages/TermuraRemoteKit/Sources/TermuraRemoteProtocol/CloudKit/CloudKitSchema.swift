import Foundation

/// Wire-level constants shared between Mac and iOS for the CloudKit transport.
/// Centralised here so a schema change updates both sides in lockstep — the
/// Mac and iOS platform-specific gateways translate `CloudKitEnvelopeRecord`
/// to/from the corresponding CKRecord using these strings.
///
/// PR7 — `currentSchemaVersion` is bumped to `2` because the on-record
/// payload shape has changed: encrypted business envelopes now sit
/// under `Field.cipher` (codec-encoded `CipherBlob`), and a new plain
/// `Field.keyId` lets routing/pruning happen without ChaChaPoly running.
/// Pair-handshake envelopes still ride in `Field.envelope` plaintext as
/// the bootstrap path because no `PairKey` exists yet between the two
/// peers; the `Field.cipher` and `Field.envelope` keys are mutually
/// exclusive and the gateway enforces it on read.
public enum CloudKitSchema {
    public static let containerIdentifier = "iCloud.com.termura.remote"
    public static let recordType = "RemoteEnvelope"

    public enum Field {
        /// Plaintext fallback used for pair-handshake envelopes only.
        /// Business envelopes after pair-complete must use `cipher`.
        public static let envelope = "envelope"
        /// Encrypted business envelope (`CipherBlob` codec-encoded as
        /// JSON / MessagePack bytes).
        public static let cipher = "cipher"
        /// `pairingId` of the `PairKey` used to seal the blob.
        /// Plaintext on the CKRecord so a reader can drop the record
        /// when it has no matching key without running ChaChaPoly.
        public static let keyId = "keyId"
        public static let targetDeviceId = "targetDeviceId"
        public static let sourceDeviceId = "sourceDeviceId"
        public static let createdAt = "createdAt"
        public static let schemaVersion = "schemaVersion"
    }

    /// Active schema version. PR7 bumps from `1` to `2`. Records with
    /// `schemaVersion < 2` are rejected by the live gateway and queued
    /// for deletion (with a warning log) — see
    /// `CloudKitGatewayError.unsupportedSchema`.
    public static let currentSchemaVersion: Int = 2
}
