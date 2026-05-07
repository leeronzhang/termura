// D-1 — drains the kit-internal `ServerTransportEvent` stream from
// the assembled CloudKit transport and forwards each entry, mapped
// to the host-facing `RemoteTransportFailure`, to the controller's
// shared `transportFailureContinuation`. Pre-fix the only signal a
// CloudKit reply-pipe had broken was a router-side log line; the
// Mac user saw the iPhone go silent with no actionable hint.
//
// WHY: the public `RemoteIntegration.transportFailures()` surface
//      promises a stable host-facing stream; the kit-internal event
//      enum stays private to TermuraRemoteServer.
// OWNER: `RemoteServerHarness` (lifetime tied to start/stop).
// CANCEL: `stop()` calls `stopTransportEventDrain()` which cancels
//         the Task; `deinit` does the same plus finishes the public
//         continuation so consumer loops fall through cleanly.
// TEST: `RemoteServerHarness+TransportEventsTests` (private repo).

import Foundation
import OSLog
import TermuraRemoteServer

private let logger = Logger(
    subsystem: "com.termura.app",
    category: "RemoteServerHarness+TransportEvents"
)

extension RemoteServerHarness {
    nonisolated func transportFailures() -> AsyncStream<RemoteTransportFailure> {
        transportFailureStream
    }

    func startTransportEventDrain(for stack: AssembledStack) {
        // Only CloudKit emits failure events today; LAN inherits the
        // protocol-extension default. Skipping the Task entirely when
        // CloudKit is off keeps the actor allocation lean for LAN-only
        // configurations and makes the no-op semantics obvious.
        guard let cloudKit = stack.cloudKit else { return }
        transportEventDrainTask?.cancel()
        let continuation = transportFailureContinuation
        transportEventDrainTask = Task {
            for await event in cloudKit.events {
                Self.forward(event: event, into: continuation)
            }
        }
    }

    func stopTransportEventDrain() {
        transportEventDrainTask?.cancel()
        transportEventDrainTask = nil
    }

    private static func forward(
        event: ServerTransportEvent,
        into continuation: AsyncStream<RemoteTransportFailure>.Continuation
    ) {
        switch event {
        case let .replyChannelSendFailed(peerDeviceId, reason, occurredAt):
            let failure = RemoteTransportFailure(
                peerDeviceId: peerDeviceId,
                reason: reason,
                occurredAt: occurredAt
            )
            continuation.yield(failure)
            logger.warning(
                """
                Reply send failed to peer \
                \(peerDeviceId.uuidString.prefix(8), privacy: .public): \
                \(reason, privacy: .public)
                """
            )
        }
    }
}
