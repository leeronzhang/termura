// PR8 Phase 2 — placeholder gateway used when CloudKit transport is
// disabled (LAN-only dev builds). The agent bridge in non-CloudKit
// mode never actually polls / saves to iCloud; this Null impl lets
// `RemoteServerHarness.AssembledStack.gateway` stay non-Optional and
// keeps the ingress / reply channel construction site simple.

import Foundation
import TermuraRemoteProtocol

struct NullCloudKitDatabaseGateway: CloudKitDatabaseGateway {
    enum Error: Swift.Error, Sendable, Equatable {
        case cloudKitDisabled
    }

    func save(_ record: CloudKitEnvelopeRecord) async throws {
        _ = record
        throw Error.cloudKitDisabled
    }

    func fetch(targetDeviceId: UUID, since: Date) async throws -> CloudKitFetchPage {
        _ = targetDeviceId
        _ = since
        return CloudKitFetchPage(records: [])
    }

    func delete(id: String) async throws {
        _ = id
        throw Error.cloudKitDisabled
    }
}
