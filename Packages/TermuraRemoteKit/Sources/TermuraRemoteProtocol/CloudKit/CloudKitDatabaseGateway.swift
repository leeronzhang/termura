import Foundation

/// Storage-agnostic operations the CloudKit transports call. The live Mac and
/// iOS impls map these to `CKContainer`/`CKDatabase`; tests use the in-memory
/// implementation below to exercise the transport state machine without
/// touching the iCloud network.
public protocol CloudKitDatabaseGateway: Sendable {
    /// Save the envelope to the peer's inbox. Idempotent w.r.t. the record id.
    func save(_ record: CloudKitEnvelopeRecord) async throws

    /// Fetch records addressed to `targetDeviceId` whose `createdAt` is strictly
    /// greater than `since`. Cursor semantics: callers persist the max
    /// `createdAt` returned and pass it back next call.
    func fetch(targetDeviceId: UUID, since: Date) async throws -> [CloudKitEnvelopeRecord]

    /// Removes a consumed record so it isn't returned by subsequent fetches.
    func delete(id: String) async throws
}

public enum CloudKitGatewayError: Error, Sendable, Equatable, LocalizedError {
    case recordNotFound(id: String)
    /// Catch-all for unexpected backing-store / network failures
    /// (CloudKit `CKError` instances, malformed CKRecord fields the
    /// parser flags as `backingFailure(reason:)`, etc.). The transport
    /// layer surfaces these as a generic poll error; they are not
    /// retried per-record.
    case backingFailure(reason: String)
    /// Gateway saw a record with `schemaVersion` lower than the active
    /// `CloudKitSchema.currentSchemaVersion`. PR7 bumps to v2 and v1
    /// records (plaintext-only) are rejected on read; the transport
    /// layer skips the entire batch with a warning rather than feeding
    /// stale data to the handler.
    ///
    /// The live gateway preserves this typed identity through `fetch`
    /// (see `LiveCloudKitDatabaseGateway.mapFetchError`). Tests cover
    /// both the gateway-side mapping and the transport-side reaction.
    case unsupportedSchema(version: Int)
    /// **Reserved for future extension.** PR7 does *not* surface this
    /// from the live gateway: ChaChaPoly tag verification happens at
    /// the **transport** layer (`CloudKitTransport.openCipher` /
    /// `CloudKitClientTransport.openCipher`), where decrypt failures
    /// are handled in-band (drop + delete + warning) without round-
    /// tripping through the gateway error type. Kept here so a future
    /// gateway-level decrypt path (e.g. a server-side reencryption
    /// passthrough) has a stable case to expose without an enum
    /// version bump. **Not asserted by any current test.**
    case decryptionFailed(reason: String)

    /// Surface the associated `reason` to UI / log lines. Without
    /// `LocalizedError`, Swift bridges the enum through NSError with a
    /// nil description, so callers doing `error.localizedDescription`
    /// see "The operation couldn't be completed.
    /// (TermuraRemoteProtocol.CloudKitGatewayError error N.)" — the
    /// underlying CKError reason ("Permission Failure",
    /// "Account temporarily unavailable", "Did not find record type",
    /// etc.) is dropped and the user gets no actionable hint about why
    /// the CloudKit-mode pair / connect failed.
    public var errorDescription: String? {
        switch self {
        case let .recordNotFound(id):
            "CloudKit record not found: \(id)"
        case let .backingFailure(reason):
            "CloudKit backing failure: \(reason)"
        case let .unsupportedSchema(version):
            "CloudKit unsupported schemaVersion=\(version)"
        case let .decryptionFailed(reason):
            "CloudKit decryption failed: \(reason)"
        }
    }
}

public actor InMemoryCloudKitDatabaseGateway: CloudKitDatabaseGateway {
    private var storage: [String: CloudKitEnvelopeRecord] = [:]

    public init(seed: [CloudKitEnvelopeRecord] = []) {
        for record in seed {
            storage[record.id] = record
        }
    }

    public func save(_ record: CloudKitEnvelopeRecord) async throws {
        storage[record.id] = record
    }

    public func fetch(targetDeviceId: UUID, since: Date) async throws -> [CloudKitEnvelopeRecord] {
        storage.values
            .filter { $0.targetDeviceId == targetDeviceId && $0.createdAt > since }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func delete(id: String) async throws {
        guard storage.removeValue(forKey: id) != nil else {
            throw CloudKitGatewayError.recordNotFound(id: id)
        }
    }

    public func snapshot() -> [CloudKitEnvelopeRecord] {
        Array(storage.values)
    }
}
