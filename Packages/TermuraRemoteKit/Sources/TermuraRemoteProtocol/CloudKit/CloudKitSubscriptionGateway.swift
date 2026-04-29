import CloudKit
import Foundation

/// Manages the long-lived `CKQuerySubscription` that fires a silent push
/// whenever a record matching `targetDeviceId == self` is created in the
/// shared private database. Once registered, the subscription persists in
/// CloudKit's per-device server-side state — no per-launch re-registration
/// needed (and re-registering with the same id is a no-op).
public protocol CloudKitSubscriptionGateway: Sendable {
    /// Registers the subscription if not already present. Idempotent — the
    /// implementation may bail out fast when `subscriptionExists()` returns true.
    func register(targetDeviceId: UUID) async throws

    /// True if the subscription is currently registered for this user.
    func subscriptionExists() async throws -> Bool

    /// Removes the subscription. Used when the user disables remote control
    /// so push wake-ups stop arriving.
    func unregister() async throws
}

public enum CloudKitSubscriptionError: Error, Sendable, Equatable {
    case backingFailure(reason: String)
}

public actor LiveCloudKitSubscriptionGateway: CloudKitSubscriptionGateway {
    private static let subscriptionID = "termura-remote-envelope-inbox"
    private let database: CKDatabase

    public init(containerIdentifier: String = CloudKitSchema.containerIdentifier) {
        let container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
    }

    public func register(targetDeviceId: UUID) async throws {
        if try await subscriptionExists() { return }
        let predicate = NSPredicate(
            format: "%K == %@",
            CloudKitSchema.Field.targetDeviceId,
            targetDeviceId.uuidString as any CVarArg
        )
        let subscription = CKQuerySubscription(
            recordType: CloudKitSchema.recordType,
            predicate: predicate,
            subscriptionID: Self.subscriptionID,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        // Silent push: no UI, just wakes the agent so it can poll the inbox.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await database.save(subscription)
        } catch {
            throw CloudKitSubscriptionError.backingFailure(reason: error.localizedDescription)
        }
    }

    public func subscriptionExists() async throws -> Bool {
        do {
            _ = try await database.subscription(for: Self.subscriptionID)
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        } catch {
            throw CloudKitSubscriptionError.backingFailure(reason: error.localizedDescription)
        }
    }

    public func unregister() async throws {
        do {
            _ = try await database.deleteSubscription(withID: Self.subscriptionID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            throw CloudKitSubscriptionError.backingFailure(reason: error.localizedDescription)
        }
    }
}

/// In-memory test double — mirrors registration state without touching CloudKit.
public actor InMemoryCloudKitSubscriptionGateway: CloudKitSubscriptionGateway {
    private var registeredFor: UUID?

    public init() {}

    public func register(targetDeviceId: UUID) async throws {
        registeredFor = targetDeviceId
    }

    public func subscriptionExists() async throws -> Bool {
        registeredFor != nil
    }

    public func unregister() async throws {
        registeredFor = nil
    }

    public func currentTarget() -> UUID? {
        registeredFor
    }
}
