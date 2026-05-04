// D-1 — drain `integration.transportFailures()` and route each
// failure into `setTransportError`. Pre-fix the CloudKit reply pipe
// could fail (CKError quota / unauthorized / network drop) and the
// Mac user saw nothing in Settings; the only signal was a router-
// side log line and a frozen iPhone session list.
//
// WHY: keep the drain off the main controller file so size budget
//      stays under §6.1 (RemoteControlController.swift is already
//      near soft cap), and so the lifecycle (start/cancel/dedupe
//      message tracking) can evolve without churning the lifecycle
//      file.
// OWNER: `RemoteControlController` (lifetime tied to enable/disable).
// CANCEL: `disable()` calls `stopTransportFailureDrain()`; `enable()`
//         failure rollback path also calls it. `deinit` finalises so
//         the Task does not outlive the controller.
// TEST: `RemoteControlController+TransportFailuresTests` (private,
//       lives in `Tests/HarnessTests/` because the assertion drives
//       a real `RemoteIntegration` that emits failures, and the only
//       integration that emits is the harness CloudKit transport.)

import Foundation
import OSLog

private let logger = Logger(
    subsystem: "com.termura.app",
    category: "RemoteControlController+TransportFailures"
)

extension RemoteControlController {
    /// Spawns the drain Task that forwards every entry from
    /// `integration.transportFailures()` into `setTransportError`.
    /// Idempotent: a second call cancels the prior Task before
    /// starting a fresh one so a re-entry from a rapid disable/enable
    /// can never leave two drains running against the same stream.
    func startTransportFailureDrain() {
        transportFailureDrainTask?.cancel()
        let stream = integration.transportFailures()
        transportFailureDrainTask = Task { [weak self] in
            for await failure in stream {
                // Cancellation is cooperative — `for await` will keep
                // delivering buffered values until the iterator's next
                // suspension, and `[weak self]` may have already been
                // released. An explicit gate here makes a buffered
                // post-stop emission a guaranteed no-op so `disable()`
                // teardown is observable, not best-effort.
                guard let self, !Task.isCancelled else { return }
                handle(failure: failure)
            }
        }
    }

    /// Tears the drain down. Safe to call when no drain is active.
    func stopTransportFailureDrain() {
        transportFailureDrainTask?.cancel()
        transportFailureDrainTask = nil
    }

    private func handle(failure: RemoteTransportFailure) {
        let peerLabel = String(failure.peerDeviceId.uuidString.prefix(8))
        let message = "Reply to \(peerLabel) failed: \(failure.reason)"
        setTransportError(message)
        logger.warning("\(message, privacy: .public)")
    }
}
