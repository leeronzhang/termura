import Foundation

/// In-memory test double for `CloudKitSubscriptionGateway`. Mirrors
/// registration state without touching CloudKit so tests (and offline
/// developer iterations) can exercise pair / register / unregister
/// flows deterministically. Lives in its own file to keep the live
/// gateway file under the size budget — the wire-level concerns
/// (CKDatabase, schema-bootstrap, legacy migration) are unrelated to
/// the in-memory mirror.
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
