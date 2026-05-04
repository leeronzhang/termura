import CloudKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.remote", category: "CloudKitSubscriptionGateway")

/// Manages a per-target `CKQuerySubscription` that fires a silent push
/// whenever a record matching `targetDeviceId == self` is created in the
/// shared private database. Subscriptions are scoped per `targetDeviceId`
/// so a Mac and an iPhone signed into the same iCloud account can each
/// register their own without colliding — the prior shared-id design
/// silently caused the second registrant's call to short-circuit on
/// `subscriptionExists` and ride the wrong predicate, which broke
/// Mac → iPhone push delivery entirely.
public protocol CloudKitSubscriptionGateway: Sendable {
    /// Idempotent. Registers a per-target subscription so records whose
    /// `targetDeviceId` matches `targetDeviceId` fire silent push to
    /// this device. Re-registering the same id is a no-op.
    func register(targetDeviceId: UUID) async throws

    /// True iff a subscription for `targetDeviceId` is currently
    /// registered for this user.
    func subscriptionExists(for targetDeviceId: UUID) async throws -> Bool

    /// Removes the subscription scoped to `targetDeviceId`. Other
    /// targets' subscriptions are left in place.
    func unregister(for targetDeviceId: UUID) async throws
}

public enum CloudKitSubscriptionError: Error, Sendable, Equatable {
    case backingFailure(reason: String)
    /// The container is operating against the Production CloudKit
    /// environment (typical for archive / distribution-signed builds)
    /// and the `RemoteEnvelope` record type has not been deployed via
    /// the CloudKit Dashboard. Apple disallows API-side schema
    /// mutation in Production, so the schema-bootstrap fallback can
    /// not recover; the operator must either deploy the schema or run
    /// a Debug-signed build that targets the Development environment.
    case schemaNotDeployed
}

extension CloudKitSubscriptionError: LocalizedError {
    /// Surface the wrapped CKError reason instead of letting Foundation's
    /// fallback render `"<Type> error 0."`. The toggle in Settings binds
    /// directly to `error.localizedDescription`, so without this
    /// conformance the user sees a stack-trace-shaped opacity instead of
    /// the actionable underlying cause.
    public var errorDescription: String? {
        switch self {
        case let .backingFailure(reason):
            "CloudKit subscription failed: \(reason)"
        case .schemaNotDeployed:
            "CloudKit cannot register the silent-push subscription because the " +
                "RemoteEnvelope record type is not deployed in this environment. " +
                "Open the CloudKit Dashboard for iCloud.com.termura.remote and " +
                "Deploy Schema Changes from Development to Production, or run a " +
                "Debug-signed build to use the Development environment."
        }
    }
}

public actor LiveCloudKitSubscriptionGateway: CloudKitSubscriptionGateway {
    /// Pre-fix shared id — both Mac and iOS used to register against
    /// this single id with their respective predicates, which caused
    /// the second registrant to short-circuit on `subscriptionExists`
    /// and silently ride the wrong predicate. Migration: every
    /// `register` best-effort deletes this so it stops firing pushes
    /// for a stale target.
    private static let legacySubscriptionID = "termura-remote-envelope-inbox"

    private static func subscriptionID(for targetDeviceId: UUID) -> String {
        "termura-remote-envelope-inbox-\(targetDeviceId.uuidString)"
    }

    private let database: CKDatabase

    public init(containerIdentifier: String = CloudKitSchema.containerIdentifier) {
        let container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
    }

    public func register(targetDeviceId: UUID) async throws {
        if try await subscriptionExists(for: targetDeviceId) { return }
        await migrateLegacyIfPresent()
        let subscription = Self.makeSubscription(targetDeviceId: targetDeviceId)
        do {
            try await saveSubscriptionWithSchemaBootstrap(subscription)
        } catch let typed as CloudKitSubscriptionError {
            // Already a typed signal (e.g. `.schemaNotDeployed` from
            // the Production-immutable bootstrap path) — keep it as-is
            // so its actionable `errorDescription` reaches the toggle.
            throw typed
        } catch {
            throw CloudKitSubscriptionError.backingFailure(reason: error.localizedDescription)
        }
    }

    static func makeSubscription(targetDeviceId: UUID) -> CKQuerySubscription {
        let predicate = NSPredicate(
            format: "%K == %@",
            CloudKitSchema.Field.targetDeviceId,
            targetDeviceId.uuidString as any CVarArg
        )
        let subscription = CKQuerySubscription(
            recordType: CloudKitSchema.recordType,
            predicate: predicate,
            subscriptionID: Self.subscriptionID(for: targetDeviceId),
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        // Silent push: no UI, just wakes the receiver so it can poll the inbox.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        return subscription
    }

    /// Cold-start companion to `LiveCloudKitDatabaseGateway.fetch`'s
    /// missing-type tolerance. A brand-new CloudKit container has no
    /// `RemoteEnvelope` schema until something saves a CKRecord of
    /// that type — `database.save(record)` auto-creates the schema in
    /// Development, but `database.save(subscription)` does NOT. So
    /// the first user to enable remote control on a fresh container
    /// hits "Did not find record type: RemoteEnvelope" and the toggle
    /// rolls back. Bootstrap by saving + deleting a placeholder
    /// record (predicate-orthogonal `targetDeviceId` so no live
    /// subscription matches it), then retry.
    ///
    /// Production fallback: schema mutation is forbidden in the
    /// Production CloudKit environment. When the placeholder save
    /// surfaces that signal, swallow the internal-implementation
    /// recordName from the user-facing message and re-throw a typed
    /// `.schemaNotDeployed` so the toggle's error gives the operator
    /// an actionable next step (deploy via Dashboard, or use a Debug
    /// build).
    private func saveSubscriptionWithSchemaBootstrap(_ subscription: CKQuerySubscription) async throws {
        do {
            _ = try await database.save(subscription)
        } catch {
            guard LiveCloudKitDatabaseGateway.isMissingRecordType(error) else { throw error }
            try await bootstrapRecordTypeSchema()
            _ = try await database.save(subscription)
        }
    }

    /// Save + delete a placeholder `RemoteEnvelope` so the schema
    /// auto-promotion for that record type takes effect. Best-effort
    /// delete: even if the placeholder lingers, real-device
    /// subscriptions (`targetDeviceId == <SHA256-derived UUID>`)
    /// never match the all-zero placeholder so it is never pushed or
    /// fetched.
    ///
    /// Throws `.schemaNotDeployed` — not the underlying CloudKit
    /// error — when the save fails on the Production environment, so
    /// the user-visible toggle error doesn't leak the internal
    /// `termura-remote-schema-bootstrap` placeholder name.
    private func bootstrapRecordTypeSchema() async throws {
        let placeholder = Self.makeSchemaBootstrapRecord()
        do {
            _ = try await database.save(placeholder)
        } catch {
            if LiveCloudKitDatabaseGateway.isProductionSchemaImmutable(error) {
                throw CloudKitSubscriptionError.schemaNotDeployed
            }
            throw error
        }
        do {
            _ = try await database.deleteRecord(withID: placeholder.recordID)
        } catch {
            // Non-critical: orphan placeholder is invisible to live
            // predicates; logged so a persistent CloudKit issue is
            // visible in Console.
            logger.warning("Schema-bootstrap placeholder cleanup failed: \(error.localizedDescription)")
        }
    }

    /// Constructs the placeholder used by `bootstrapRecordTypeSchema`.
    /// Static + module-internal so unit tests can pin the field shape
    /// without standing up `CKDatabase`. Field values are chosen so
    /// CloudKit accepts the save (each field gets a typed
    /// non-nil value, auto-promoting the schema), and so the
    /// resulting record never matches any real subscription
    /// predicate or fetch query (real device ids are SHA-256-derived
    /// UUIDs and can never collide with the all-zero placeholder).
    static func makeSchemaBootstrapRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: "termura-remote-schema-bootstrap")
        let record = CKRecord(recordType: CloudKitSchema.recordType, recordID: recordID)
        let zeroId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            .uuidString as NSString
        record[CloudKitSchema.Field.targetDeviceId] = zeroId
        record[CloudKitSchema.Field.sourceDeviceId] = zeroId
        record[CloudKitSchema.Field.createdAt] = Date.distantPast as NSDate
        record[CloudKitSchema.Field.schemaVersion] = CloudKitSchema.currentSchemaVersion as NSNumber
        record[CloudKitSchema.Field.envelope] = Data() as NSData
        return record
    }

    public func subscriptionExists(for targetDeviceId: UUID) async throws -> Bool {
        do {
            _ = try await database.subscription(for: Self.subscriptionID(for: targetDeviceId))
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        } catch {
            throw CloudKitSubscriptionError.backingFailure(reason: error.localizedDescription)
        }
    }

    public func unregister(for targetDeviceId: UUID) async throws {
        do {
            _ = try await database.deleteSubscription(withID: Self.subscriptionID(for: targetDeviceId))
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            throw CloudKitSubscriptionError.backingFailure(reason: error.localizedDescription)
        }
    }

    /// One-shot best-effort cleanup of the pre-fix shared subscription
    /// id. Failures (other than "not present") leave an orphan
    /// subscription server-side but do not block the new per-target
    /// registration that follows; logged so a persistent backend
    /// issue surfaces in Console.
    private func migrateLegacyIfPresent() async {
        do {
            _ = try await database.deleteSubscription(withID: Self.legacySubscriptionID)
        } catch let error as CKError where error.code == .unknownItem {
            // Migration already ran (or the legacy id was never created).
        } catch {
            // Non-critical: logged for visibility, registration continues.
            logger.warning("Legacy subscription cleanup failed: \(error.localizedDescription)")
        }
    }
}
