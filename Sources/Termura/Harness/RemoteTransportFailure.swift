// Host-facing view of a transport failure surfaced via
// `RemoteIntegration.transportFailures()`. Decoupled from the
// kit-internal `ServerTransportEvent` so the public controller
// surface does not pull TermuraRemoteServer types into the
// `Sources/Termura/Harness/` stub. Lives here (with the empty
// default impl) so the adjacent `RemoteIntegration+Stub.swift`
// stays under the file_length soft cap (CLAUDE.md §6.1).

import Foundation

struct RemoteTransportFailure: Sendable, Equatable {
    let peerDeviceId: UUID
    let reason: String
    let occurredAt: Date
}

extension RemoteIntegration {
    func transportFailures() -> AsyncStream<RemoteTransportFailure> {
        AsyncStream { continuation in continuation.finish() }
    }
}
