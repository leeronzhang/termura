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
        do {
            _ = try await database.save(subscription)
        } catch {
            throw CloudKitSubscriptionError.backingFailure(reason: error.localizedDescription)
        }
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

/// In-memory test double — mirrors registration state without touching CloudKit.
public actor InMemoryCloudKitSubscriptionGateway: CloudKitSubscriptionGateway {
    private var registeredTargets: Set<UUID> = []

    public init() {}

    public func register(targetDeviceId: UUID) async throws {
        registeredTargets.insert(targetDeviceId)
    }

    public func subscriptionExists(for targetDeviceId: UUID) async throws -> Bool {
        registeredTargets.contains(targetDeviceId)
    }

    public func unregister(for targetDeviceId: UUID) async throws {
        registeredTargets.remove(targetDeviceId)
    }

    public func registeredTargetIds() -> Set<UUID> {
        registeredTargets
    }
}
