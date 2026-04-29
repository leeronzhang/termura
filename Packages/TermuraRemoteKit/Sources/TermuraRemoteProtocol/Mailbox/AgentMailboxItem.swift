import Foundation

/// PR8 Phase 2 — transport-neutral mailbox item carrying one CloudKit
/// `CloudKitEnvelopeRecord` from the LaunchAgent process to the main
/// app process over XPC. The wire shape is intentionally agnostic to
/// whether the underlying record was a `.plaintext(Envelope)` or a
/// `.cipher(CipherBlob)` — `payloadKind` discriminates so the ingress
/// can pick the right decoder without inspecting bytes.
///
/// Field domain conventions (PR8 §3.1):
/// - `recordName`: human-readable CloudKit record id. **Used only for
///   diagnostics, log lines, `gateway.delete(recordName:)` addressing,
///   and quarantine table key.** Never used for cursor advancement.
/// - `createdAt`: server-assigned timestamp. **The single source of
///   truth for cursor advancement** (`gateway.fetch(since:)` is keyed
///   on `Date`, so cursor is `Date` too). Never used for record
///   identity.
/// - `sourceDeviceId`: the **cloudSourceDeviceId** domain — the
///   public-key-derived id the iPhone uses on every CloudKit envelope
///   it sends. Never the `pairedDeviceId` domain.
/// - `payloadKind` + `payloadData`: contract — `.plaintext` ⇒
///   `payloadData` is `JSONEncoder.encode(Envelope)`; `.cipher` ⇒
///   `payloadData` is `JSONEncoder.encode(CipherBlob)`. Both encodings
///   stay JSON because the agent has no codec context (codec
///   negotiation happens inside the app).
public struct AgentMailboxItem: Sendable, Equatable, Codable {
    public enum PayloadKind: String, Sendable, Codable, CaseIterable, Equatable {
        case plaintext
        case cipher
    }

    public let recordName: String
    public let createdAt: Date
    public let sourceDeviceId: UUID
    public let payloadKind: PayloadKind
    public let payloadData: Data
    public let schemaVersion: Int

    /// Current wire schema. Bumped only when an incompatible field
    /// shape change lands; readers reject items whose `schemaVersion`
    /// doesn't match the current value (rather than silently
    /// degrading) so a partial roll-out can't pollute the mailbox.
    public static let currentSchemaVersion: Int = 1

    public init(
        recordName: String,
        createdAt: Date,
        sourceDeviceId: UUID,
        payloadKind: PayloadKind,
        payloadData: Data,
        schemaVersion: Int = AgentMailboxItem.currentSchemaVersion
    ) {
        self.recordName = recordName
        self.createdAt = createdAt
        self.sourceDeviceId = sourceDeviceId
        self.payloadKind = payloadKind
        self.payloadData = payloadData
        self.schemaVersion = schemaVersion
    }
}
