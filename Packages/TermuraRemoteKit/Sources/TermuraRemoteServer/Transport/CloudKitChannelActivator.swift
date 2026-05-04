import Foundation

/// Wave 5 — abstraction the routing layer calls when it needs to flip
/// a CloudKit reply channel from plaintext-bootstrap mode to encrypted
/// mode after a successful pair / rejoin handshake. Pre-Wave-5 the
/// router took a closure-typed `(UUID, UUID) async -> Void` activator
/// that nobody could read at a glance; the protocol form gives the
/// call site a self-documenting name and lets test doubles be injected
/// without tripping `@Sendable` capture-list awkwardness.
///
/// `forSourceDeviceId` is the `cloudSourceDeviceId` (public-key-derived
/// id the iPhone uses on every CloudKit envelope it sends).
/// `pairingId` is the id under which both peers persist the derived
/// `PairKey`. A no-op default is provided so harness builds without a
/// CloudKit transport (LAN-only) can pass a single canned instance
/// instead of threading an Optional everywhere.
public protocol CloudKitChannelActivator: Sendable {
    func activate(pairingId: UUID, forSourceDeviceId source: UUID) async
}

/// Default no-op activator used when CloudKit transport is gated off.
/// LAN-only pairs never need encryption activation; routing the no-op
/// through the protocol keeps the router's call-site free of
/// `if let activator =` Optional handling.
public struct NullCloudKitChannelActivator: CloudKitChannelActivator {
    public init() {}

    public func activate(pairingId: UUID, forSourceDeviceId source: UUID) async {
        _ = pairingId
        _ = source
    }
}
