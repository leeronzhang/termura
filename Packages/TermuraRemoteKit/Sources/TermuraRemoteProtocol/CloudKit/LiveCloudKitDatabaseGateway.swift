import CloudKit
import Foundation

/// Real-network implementation of `CloudKitDatabaseGateway` backed by
/// `CKContainer.privateCloudDatabase`. Translates each
/// `CloudKitEnvelopeRecord` to/from a `CKRecord` using `CloudKitSchema.Field.*`
/// keys so the schema in the CloudKit Dashboard mirrors the record type.
///
/// Queryable indexes required (set in CloudKit Dashboard):
///   - `targetDeviceId` — Queryable
///   - `createdAt`      — Queryable + Sortable
///
/// PR7 — payload now has two mutually-exclusive shapes:
///   * encrypted `cipher: Data` (the codec-encoded `CipherBlob`)
///   * plaintext `envelope: Data` (codec-encoded `Envelope`, used only
///     for the pair-handshake bootstrap on cross-network initial pair)
/// `keyId` is plaintext on the CKRecord for the cipher branch so a
/// reader without the matching `PairKey` can drop the record without
/// running ChaChaPoly. Records with `schemaVersion < currentSchemaVersion`
/// throw `unsupportedSchema` so the transport can purge v1 leftovers.
public actor LiveCloudKitDatabaseGateway: CloudKitDatabaseGateway {
    private let database: CKDatabase
    private let codec: any RemoteCodec

    public init(
        containerIdentifier: String = CloudKitSchema.containerIdentifier,
        codec: any RemoteCodec = JSONRemoteCodec()
    ) {
        let container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        self.codec = codec
    }

    public func save(_ record: CloudKitEnvelopeRecord) async throws {
        let ckRecord = try Self.makeCKRecord(from: record, codec: codec)
        do {
            _ = try await database.save(ckRecord)
        } catch {
            throw CloudKitGatewayError.backingFailure(reason: error.localizedDescription)
        }
    }

    public func fetch(targetDeviceId: UUID, since: Date) async throws -> CloudKitFetchPage {
        let predicate = NSPredicate(
            format: "%K == %@ AND %K > %@",
            CloudKitSchema.Field.targetDeviceId,
            targetDeviceId.uuidString as any CVarArg,
            CloudKitSchema.Field.createdAt,
            since as NSDate
        )
        let query = CKQuery(recordType: CloudKitSchema.recordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: CloudKitSchema.Field.createdAt, ascending: true)
        ]
        do {
            let result = try await database.records(matching: query)
            return Self.parseFetchResults(result.matchResults, codec: codec)
        } catch {
            // Cold-start bootstrap: a freshly-provisioned CloudKit
            // container has no `RemoteEnvelope` record type until the
            // first `save()` auto-creates it (Development env) or it is
            // deployed via the Dashboard (Production env). Both Mac
            // (`CloudKitTransport.start`) and iOS
            // (`CloudKitClientTransport.connect`) probe via fetch before
            // anyone has saved anything — chicken-and-egg. CKError
            // surfaces this as `Did not find record type: <name>`
            // (CKInternalErrorDomain code 2003, exposed at the public
            // layer as `CKError.unknownItem`). Treating it as an empty
            // result is semantically correct and lets the very first
            // handshake `save()` auto-create the type. Tests pin both
            // the detection helper and this fetch behaviour.
            if Self.isMissingRecordType(error) {
                return CloudKitFetchPage(records: [])
            }
            throw Self.mapFetchError(error)
        }
    }

    /// Per-record isolation: each `parseRecord` failure (legacy schema,
    /// malformed fields, payload shape mismatch) lands in `quarantined`
    /// instead of failing the whole fetch. Static so tests can exercise
    /// the policy without standing up CKContainer; the transport relies
    /// on `quarantined.createdAt` (when readable) to advance its cursor
    /// past the poison record.
    static func parseFetchResults(
        _ matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)],
        codec: any RemoteCodec
    ) -> CloudKitFetchPage {
        var parsed: [CloudKitEnvelopeRecord] = []
        var quarantined: [QuarantinedRecord] = []
        for (recordID, outcome) in matchResults {
            switch outcome {
            case let .success(ckRecord):
                do {
                    let record = try parseRecord(ckRecord, codec: codec)
                    parsed.append(record)
                } catch {
                    quarantined.append(QuarantinedRecord(
                        id: recordID.recordName,
                        createdAt: ckRecord[CloudKitSchema.Field.createdAt] as? Date,
                        reason: error.localizedDescription
                    ))
                }
            case let .failure(error):
                // Per-record fetch failure (e.g. asset missing, partial
                // record). Surface so the caller can delete the entry
                // — createdAt is unknown in this branch.
                quarantined.append(QuarantinedRecord(
                    id: recordID.recordName,
                    createdAt: nil,
                    reason: error.localizedDescription
                ))
            }
        }
        return CloudKitFetchPage(records: parsed, quarantined: quarantined)
    }

    /// Error-mapping policy for `fetch`'s catch:
    ///
    ///   * `CloudKitGatewayError` instances from `parseRecord` (today
    ///     `unsupportedSchema(version:)` and `backingFailure(reason:)`
    ///     for malformed CKRecords) are re-raised verbatim — the
    ///     transport relies on the typed identity to skip the batch
    ///     with the right diagnostic.
    ///   * Anything else (network errors out of `database.records(...)`
    ///     etc.) gets wrapped in `backingFailure(reason:)` so callers
    ///     have a single shape to reason about for transport-layer
    ///     surfacing.
    ///
    /// `static` so `LiveCloudKitGatewayTests` can exercise the policy
    /// without standing up a real CKContainer.
    static func mapFetchError(_ error: any Error) -> CloudKitGatewayError {
        if let typed = error as? CloudKitGatewayError {
            return typed
        }
        return .backingFailure(reason: error.localizedDescription)
    }

    /// Detects "record type does not exist yet" — surfaced by CloudKit as
    /// `CKError.unknownItem` at the public layer, or as
    /// `CKInternalErrorDomain` code 2003 underneath, with a message of
    /// the form `"Did not find record type: <Name>"`. We check all three
    /// signals (typed CKError, NSError domain+code, and a literal
    /// substring match) so the detection survives Apple's occasional
    /// reshuffling of which layer surfaces this state. Used by `fetch`
    /// to short-circuit cold-start fetches into an empty result; **not**
    /// used for `save`/`delete` (those should propagate so a misconfigured
    /// container isn't silently masked once writes start).
    static func isMissingRecordType(_ error: any Error) -> Bool {
        if let ckError = error as? CKError, ckError.code == .unknownItem {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == "CKInternalErrorDomain", nsError.code == 2003 {
            return true
        }
        return nsError.localizedDescription.contains("Did not find record type")
    }

    public func delete(id: String) async throws {
        do {
            _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: id))
        } catch let error as CKError where error.code == .unknownItem {
            throw CloudKitGatewayError.recordNotFound(id: id)
        } catch {
            throw CloudKitGatewayError.backingFailure(reason: error.localizedDescription)
        }
    }

    static func makeCKRecord(
        from record: CloudKitEnvelopeRecord,
        codec: any RemoteCodec
    ) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: record.id)
        let ckRecord = CKRecord(recordType: CloudKitSchema.recordType, recordID: recordID)
        switch record.payload {
        case let .cipher(blob):
            let encoded = try codec.encode(blob)
            ckRecord[CloudKitSchema.Field.cipher] = encoded as NSData
            ckRecord[CloudKitSchema.Field.keyId] = blob.keyId.uuidString as NSString
        case let .plaintext(envelope):
            let encoded = try codec.encode(envelope)
            ckRecord[CloudKitSchema.Field.envelope] = encoded as NSData
        }
        ckRecord[CloudKitSchema.Field.targetDeviceId] = record.targetDeviceId.uuidString as NSString
        ckRecord[CloudKitSchema.Field.sourceDeviceId] = record.sourceDeviceId.uuidString as NSString
        ckRecord[CloudKitSchema.Field.createdAt] = record.createdAt as NSDate
        ckRecord[CloudKitSchema.Field.schemaVersion] = record.schemaVersion as NSNumber
        return ckRecord
    }

    static func parseRecord(
        _ ckRecord: CKRecord,
        codec: any RemoteCodec
    ) throws -> CloudKitEnvelopeRecord {
        guard
            let targetIdString = ckRecord[CloudKitSchema.Field.targetDeviceId] as? String,
            let sourceIdString = ckRecord[CloudKitSchema.Field.sourceDeviceId] as? String,
            let createdAt = ckRecord[CloudKitSchema.Field.createdAt] as? Date,
            let targetId = UUID(uuidString: targetIdString),
            let sourceId = UUID(uuidString: sourceIdString)
        else {
            throw CloudKitGatewayError.backingFailure(reason: "malformed CKRecord fields")
        }
        let schemaVersion = (ckRecord[CloudKitSchema.Field.schemaVersion] as? Int)
            ?? CloudKitSchema.currentSchemaVersion
        if schemaVersion < CloudKitSchema.currentSchemaVersion {
            throw CloudKitGatewayError.unsupportedSchema(version: schemaVersion)
        }
        let payload = try Self.parsePayload(ckRecord, codec: codec)
        return CloudKitEnvelopeRecord(
            id: ckRecord.recordID.recordName,
            payload: payload,
            targetDeviceId: targetId,
            sourceDeviceId: sourceId,
            createdAt: createdAt,
            schemaVersion: schemaVersion
        )
    }

    private static func parsePayload(
        _ ckRecord: CKRecord,
        codec: any RemoteCodec
    ) throws -> CloudKitEnvelopeRecord.Payload {
        let cipherData = ckRecord[CloudKitSchema.Field.cipher] as? Data
        let envelopeData = ckRecord[CloudKitSchema.Field.envelope] as? Data
        switch (cipherData, envelopeData) {
        case let (.some(bytes), .none):
            let blob = try codec.decode(CipherBlob.self, from: bytes)
            return .cipher(blob)
        case let (.none, .some(bytes)):
            let envelope = try codec.decode(Envelope.self, from: bytes)
            return .plaintext(envelope)
        case (.some, .some):
            throw CloudKitGatewayError.backingFailure(
                reason: "record has both cipher and envelope fields; expected exactly one"
            )
        case (.none, .none):
            throw CloudKitGatewayError.backingFailure(
                reason: "record missing both cipher and envelope fields"
            )
        }
    }
}
