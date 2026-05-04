// PR9 v2.2 §10.1 — destructive user actions for the Remote Control
// surface live here, separate from the lifecycle / state file. Three
// actions, broken out by destructiveness:
//
//   * `revokeDevice(id:)` — least destructive; flips one device's
//                            `revokedAt`. Does not touch transports.
//   * `revokeAll()`        — flips every active device. Same scope.
//   * `disable()`          — tears down transports + LaunchAgent plist
//                            but preserves paired devices, pair keys,
//                            identity, audit log, agent cursor /
//                            quarantine.
//   * `resetPairings()`    — most destructive; runs disable then wipes
//                            harness-side pairing state and asks the
//                            agent to wipe cursor / quarantine. Routes
//                            an XPC failure through a β probe and a
//                            keychain B-fallback when the probe
//                            confirms agent is unreachable.
//
// All four UI actions guard on `isWorking` so they can't overlap.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteControlController+Actions")

extension RemoteControlController {
    // MARK: - revokeDevice

    /// Marks the device as revoked. Subsequent envelopes from that device id
    /// are rejected by the router. Refreshes the local list on success.
    /// PR9 Step 1 made the underlying `PairingService.revoke(deviceId:)`
    /// idempotent — re-revoking a device whose `revokedAt` is already
    /// set is a silent no-op rather than a thrown `notFound`, so this
    /// path no longer surfaces a phantom "Revoke failed" error on UI
    /// double-taps or queued action races.
    func revokeDevice(id: UUID) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await integration.revokePairedDevice(id: id)
            await refreshDevicesAndAudit()
            clearLastError()
        } catch {
            setOtherError("Revoke failed: \(error.localizedDescription)")
            logger.error("Revoke failed: \(error.localizedDescription)")
        }
    }

    // MARK: - revokeAll

    /// PR9 — bulk revoke. Walks every active paired device and marks
    /// it `revokedAt`; already-revoked entries are silently skipped
    /// (handled by the harness via `PairingService.revokeAll`). The
    /// transport layer, the LaunchAgent plist, the cursor / quarantine
    /// keychain stores, and the persisted `enabled` flag are all
    /// **untouched** — `revokeAll` is intentionally narrower than
    /// `disable` / `resetPairings` so a user can keep remote control
    /// running and immediately invite a new device after revoking the
    /// existing fleet.
    ///
    /// Failure modes:
    /// - Partial — some devices got revoked, some failed to persist.
    ///   `lastError` carries a "X device(s) could not be revoked"
    ///   summary; successful revocations stay (no rollback). The list
    ///   is still refreshed so the UI reflects the partial outcome.
    /// - Total — the harness couldn't even load the device list (e.g.
    ///   keychain unavailable). `lastError` carries the localized
    ///   description; the list is not refreshed (it would have failed
    ///   anyway).
    func revokeAll() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await integration.revokeAllPairedDevices()
            await refreshDevicesAndAudit()
            clearLastError()
        } catch let RemoteAdapterError.partialRevokeAllFailed(failed) {
            let summary = failed.map { String($0.uuidString.prefix(8)) }.joined(separator: ", ")
            setOtherError("\(failed.count) device(s) could not be revoked: \(summary)")
            logger.error("revokeAll partial failure: \(failed.count) failed")
            await refreshDevicesAndAudit()
        } catch {
            setOtherError("Revoke all failed: \(error.localizedDescription)")
            logger.error("Revoke all failed: \(error.localizedDescription)")
        }
    }

    // MARK: - disable

    /// PR9 v2.2 §12.1 sequence:
    ///   1. `agentBridge.stop()`         — mute the agent ↔ app inbound path
    ///   2. `integration.stop()`         — stop transports + unregister sub
    ///   3. `installer.uninstall(...)`   — `launchctl bootout` + del plist
    ///   4. `setEnabledFlag(false)`      — persist user's off intent
    /// Plist uninstall is the only soft-failure step; failure does NOT
    /// gate the disabled state because the next enable would idempotently
    /// reinstall anyway. Bridge / integration stop are async-not-throws.
    /// Disable does NOT touch paired devices, pair keys, identity, audit
    /// log, agent cursor / quarantine — those are revokeAll / resetPairings
    /// territory.
    func disable() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await tearDownTransports()
        let uninstallError = await uninstallAgentArtifacts()
        setEnabledFlag(false)
        latestInvitationJSON = nil
        if let uninstallError {
            setOtherError("LaunchAgent plist removal failed: \(uninstallError)")
        } else {
            clearLastError()
        }
        logger.info("Remote control disabled")
    }
}
