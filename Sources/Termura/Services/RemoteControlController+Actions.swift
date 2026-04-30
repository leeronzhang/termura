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
            lastError = nil
        } catch {
            lastError = "Revoke failed: \(error.localizedDescription)"
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
            lastError = nil
        } catch let RemoteAdapterError.partialRevokeAllFailed(failed) {
            let summary = failed.map { String($0.uuidString.prefix(8)) }.joined(separator: ", ")
            lastError = "\(failed.count) device(s) could not be revoked: \(summary)"
            logger.error("revokeAll partial failure: \(failed.count) failed")
            await refreshDevicesAndAudit()
        } catch {
            lastError = "Revoke all failed: \(error.localizedDescription)"
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
            lastError = "LaunchAgent plist removal failed: \(uninstallError)"
        } else {
            lastError = nil
        }
        logger.info("Remote control disabled")
    }

    // MARK: - resetPairings

    /// PR9 v2.2 §12.3 — most destructive action. Sequence:
    ///
    ///   1-2. If currently enabled, run an inline disable (without
    ///        going through `disable()` — that would deadlock on
    ///        `isWorking`) so we start from a known-stopped state.
    ///   3.   Re-install the LaunchAgent plist so `launchctl` can
    ///        demand-launch the agent for one-shot RPC.
    ///   4.   `agentBridge.start()` — opens the XPC client side.
    ///   5a.  `integration.resetPairingState()` — wipes harness-side
    ///        PairedDevice + PairKey stores. Hard failure aborts;
    ///        no fallback B from this path because step 5b never ran.
    ///   5b.  `agentBridge.resetAgentState()` — XPC RPC asking the
    ///        agent to wipe cursor + quarantine. Soft failure flips
    ///        `step5bFailed`; the controller still tears down and
    ///        decides between γ and B based on the probe.
    ///   6.   `agentBridge.stop()`              — soft
    ///   7.   `installer.uninstall(...)`        — soft
    ///   7.5. (only if 5b failed) `agentDeathProbe.confirmUnreachable`
    ///        — 5s grace + fresh-connection probe + 1s timeout.
    ///
    ///        **§12.6.1 invariant**: step 6 / 7 soft failures must
    ///        NOT short-circuit the probe. Fallback B's safety
    ///        depends entirely on the probe's `.confirmedDead`
    ///        result, never on whether `stop()` / `uninstall()`
    ///        returned cleanly.
    ///
    ///   8.   If `step5bFailed && probe == .confirmedDead`,
    ///        run `fallbackCleaner.cleanCursorAndQuarantine()` (B).
    ///        Otherwise on `step5bFailed` route to γ: write a
    ///        partial-completion `lastError`, never call B.
    ///   9.   `setEnabledFlag(false)` — idempotent persist.
    ///   10.  Refresh devices / audit so the UI reflects the
    ///        post-reset state.
    func resetPairings() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        if isEnabled {
            await inlineDisableForReset()
        }
        do {
            try await installer.install(plistConfig)
        } catch {
            lastError = "Reset failed before agent reset: plist install error: \(error.localizedDescription)"
            logger.error("resetPairings step 3 install failed: \(error.localizedDescription)")
            await refreshDevicesAndAudit()
            return
        }
        await agentBridge.start()
        do {
            try await integration.resetPairingState()
        } catch {
            await abortAfterStep5aFailure(error: error)
            return
        }
        let step5bFailed = await runStep5bAgentReset()
        await agentBridge.stop()
        let uninstallError = await uninstallAgentArtifacts()
        await composeResetOutcome(
            step5bFailed: step5bFailed,
            uninstallError: uninstallError
        )
        setEnabledFlag(false)
        await refreshDevicesAndAudit()
    }

    // MARK: - Private helpers

    /// Step 1-2 inlined. Cannot delegate to `disable()` because it
    /// guards on `isWorking` (already true here). Identical body.
    private func inlineDisableForReset() async {
        await tearDownTransports()
        _ = await uninstallAgentArtifacts()
        setEnabledFlag(false)
        latestInvitationJSON = nil
    }

    /// Step 5a hard-failure cleanup. Stops the bridge, uninstalls the
    /// plist, persists `enabled = false`, and refreshes the UI list.
    /// Does NOT trigger β probe / fallback B — step 5b never ran, so
    /// the agent's keychain state is intact and not our concern.
    private func abortAfterStep5aFailure(error: Error) async {
        lastError = "Reset failed at pairing wipe: \(error.localizedDescription)"
        logger.error("resetPairings step 5a failed: \(error.localizedDescription)")
        await agentBridge.stop()
        _ = await uninstallAgentArtifacts()
        setEnabledFlag(false)
        await refreshDevicesAndAudit()
    }

    /// Step 5b — XPC RPC to ask the agent to wipe its cursor +
    /// quarantine. Returns whether the call failed; the caller drives
    /// the β / γ / B decision based on this flag.
    private func runStep5bAgentReset() async -> Bool {
        do {
            try await agentBridge.resetAgentState()
            return false
        } catch {
            logger.warning("resetPairings step 5b failed: \(error.localizedDescription)")
            return true
        }
    }

    /// Step 7.5 + 8 — β probe (only when step 5b failed) and the
    /// γ-vs-B fallback decision. §12.6.1 invariant: step 6 / step 7
    /// soft failures must NOT short-circuit the probe; that's
    /// preserved here because the caller always reaches this method.
    private func composeResetOutcome(
        step5bFailed: Bool,
        uninstallError: String?
    ) async {
        guard step5bFailed else {
            lastError = uninstallError.map { "Reset completed but plist removal failed: \($0)" }
            return
        }
        let probeResult = await agentDeathProbe.confirmUnreachable(
            machServiceName: plistConfig.label
        )
        switch probeResult {
        case .confirmedDead:
            await fallbackCleaner.cleanCursorAndQuarantine()
            lastError = "Agent reset via fallback: agent unreachable but agent state cleared via keychain."
        case .possiblyAlive:
            lastError = "Reset partially completed: agent still reachable; agent state retained, retry reset."
        case .indeterminate:
            lastError = "Reset partially completed: agent death unconfirmed; agent state retained."
        }
    }

    /// Sequenced transport teardown — bridge first (so no fresh
    /// envelope can land in the router while we're stopping the
    /// server), then integration. Both APIs are async-not-throws.
    private func tearDownTransports() async {
        await agentBridge.stop()
        await integration.stop()
    }

    /// Best-effort plist uninstall. Returns the localized description
    /// of any throw so callers can fold it into their own `lastError`
    /// composition without making this a hard-failure step.
    private func uninstallAgentArtifacts() async -> String? {
        do {
            try await installer.uninstall(label: plistConfig.label)
            return nil
        } catch {
            logger.warning("plist uninstall failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}
