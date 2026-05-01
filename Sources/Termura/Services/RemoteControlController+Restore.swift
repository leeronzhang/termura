// Cold-start `restoreIfEnabled()`. Lives in its own extension so the
// controller's main file stays under the 250-line soft cap; functionally
// part of the same observable type as `RemoteControlController`.

import Foundation
import OSLog

private let logger = Logger(
    subsystem: "com.termura.app",
    category: "RemoteControlController+Restore"
)

extension RemoteControlController {
    /// Cold-start counterpart to `enable()`. The `remoteControlEnabled`
    /// UserDefault survives across launches but `integration.start()`
    /// has to run again every process to bring the harness server,
    /// router, and broadcast subscription back online; without this,
    /// paired iOS clients see a stale "paired but no sessions" UI
    /// until the user manually toggles Settings off and on.
    ///
    /// Skips the helper-bundle validation and LaunchAgent install
    /// steps that `enable()` performs — those are user-initiated
    /// preconditions, and `scheduleReinstallIfNeeded` already keeps
    /// the installed plist aligned with the current bundle. Re-running
    /// either at every launch would double work and miss the §7.2
    /// launch P95 budget.
    ///
    /// Failure is non-fatal: `lastError` surfaces so the Settings UI
    /// can prompt the user to retry via the explicit toggle path,
    /// which routes through `enable()` with the full validation gate.
    /// `isEnabled` is intentionally left at `true` so the toggle keeps
    /// reflecting user intent.
    func restoreIfEnabled() async {
        guard isEnabled, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await integration.start()
            clearLastError()
            logger.info("Remote integration restored from persisted enabled state")
        } catch {
            setOtherError(error.localizedDescription)
            logger.error(
                "Failed to restore remote integration at launch: \(error.localizedDescription)"
            )
        }
    }
}
