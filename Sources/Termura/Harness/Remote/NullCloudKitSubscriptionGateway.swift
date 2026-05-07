// Production no-op used when CloudKit transport is disabled
// (`TERMURA_REMOTE_DISABLE_CLOUDKIT=1` opt-out kill-switch).
// Mirrors `NullCloudKitDatabaseGateway` so
// `RemoteServerHarness.AssembledStack.subscriptionGateway` stays non-
// Optional and the start / stop / register paths can keep their
// existing `if stack.cloudKit != nil` gating without a second nil
// check on the gateway.
//
// Constructing `LiveCloudKitSubscriptionGateway` traps hard when the
// `com.apple.developer.icloud-services` entitlement is missing — a
// `CKContainer(identifier:)` significant-issue assert that cannot be
// caught from Swift. The harness must therefore avoid instantiating
// the live gateway whenever CloudKit is gated off, and this Null
// stand-in is what fills the slot.

import Foundation
import TermuraRemoteProtocol

actor NullCloudKitSubscriptionGateway: CloudKitSubscriptionGateway {
    enum Error: Swift.Error, Sendable, Equatable {
        case cloudKitDisabled
    }

    init() {}

    func register(targetDeviceId: UUID) async throws {
        _ = targetDeviceId
        throw Error.cloudKitDisabled
    }

    func subscriptionExists(for targetDeviceId: UUID) async throws -> Bool {
        _ = targetDeviceId
        return false
    }

    func unregister(for targetDeviceId: UUID) async throws {
        _ = targetDeviceId
        throw Error.cloudKitDisabled
    }
}
