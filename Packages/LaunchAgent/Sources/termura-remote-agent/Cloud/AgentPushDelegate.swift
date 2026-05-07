// PR8 Phase 2 — silent-push hook stub. Future PR wires APNs into
// the agent process; for now the runner exposes `pollOnce()` that
// the delegate can call when a push arrives.

import Foundation

@MainActor
final class AgentPushDelegate {
    private let runner: AgentCloudKitRunner

    init(runner: AgentCloudKitRunner) {
        self.runner = runner
    }

    /// Invoke from the silent-push handler (or test) to force the
    /// runner to poll immediately rather than wait for the periodic
    /// timer to tick.
    func didReceiveRemoteNotification() {
        Task { [runner] in
            await runner.pollOnce()
        }
    }
}
