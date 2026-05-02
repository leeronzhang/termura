// PR9 v2.2 §10.1 — `resetPairings()` and its private helpers, split
// from `+Actions.swift` so the action file stays under §6.1's
// 250-line soft cap. Reset is the most destructive remote-control
// action: it runs disable, wipes harness-side pairing state, and
// asks the agent to wipe cursor / quarantine. An XPC failure routes
// through a β probe + keychain B-fallback when the probe confirms
// the agent is unreachable.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteControlController.Reset")

extension RemoteControlController {
    /// Full destructive reset orchestration. See `+Actions.swift`
    /// header for the action taxonomy and §12.6.1 for the step
    /// ordering invariant (β probe must always run when step 5b
    /// failed, regardless of step 6 / step 7 soft failures).
    func resetPairings() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        if isEnabled {
            await inlineDisableForReset()
        }
        do {
            try await installer.install(runtimePlistConfig())
            recordFingerprintAfterInstall()
        } catch {
            setOtherError(
                "Reset failed before agent reset: plist install error: \(error.localizedDescription)"
            )
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

    // MARK: - Reset private helpers

    /// Step 1-2 inlined. Cannot delegate to `disable()` because it
    /// guards on `isWorking` (already true here). Identical body.
    func inlineDisableForReset() async {
        await tearDownTransports()
        _ = await uninstallAgentArtifacts()
        setEnabledFlag(false)
        latestInvitationJSON = nil
    }

    /// Step 5a hard-failure cleanup. Stops the bridge, uninstalls the
    /// plist, persists `enabled = false`, and refreshes the UI list.
    /// Does NOT trigger β probe / fallback B — step 5b never ran, so
    /// the agent's keychain state is intact and not our concern.
    func abortAfterStep5aFailure(error: Error) async {
        setOtherError("Reset failed at pairing wipe: \(error.localizedDescription)")
        logger.error("resetPairings step 5a failed: \(error.localizedDescription)")
        await agentBridge.stop()
        _ = await uninstallAgentArtifacts()
        setEnabledFlag(false)
        await refreshDevicesAndAudit()
    }

    /// Step 5b — XPC RPC to ask the agent to wipe its cursor +
    /// quarantine. Returns whether the call failed; the caller drives
    /// the β / γ / B decision based on this flag.
    func runStep5bAgentReset() async -> Bool {
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
    func composeResetOutcome(
        step5bFailed: Bool,
        uninstallError: String?
    ) async {
        guard step5bFailed else {
            if let uninstallError {
                setOtherError("Reset completed but plist removal failed: \(uninstallError)")
            } else {
                clearLastError()
            }
            return
        }
        let probeResult = await agentDeathProbe.confirmUnreachable(
            machServiceName: agentMetadata.label
        )
        switch probeResult {
        case .confirmedDead:
            await fallbackCleaner.cleanCursorAndQuarantine()
            setOtherError(
                "Agent reset via fallback: agent unreachable but agent state cleared via keychain."
            )
        case .possiblyAlive:
            setOtherError(
                "Reset partially completed: agent still reachable; agent state retained, retry reset."
            )
        case .indeterminate:
            setOtherError("Reset partially completed: agent death unconfirmed; agent state retained.")
        }
    }

    /// Sequenced transport teardown — bridge first (so no fresh
    /// envelope can land in the router while we're stopping the
    /// server), then integration. Both APIs are async-not-throws.
    func tearDownTransports() async {
        await agentBridge.stop()
        await integration.stop()
    }

    /// Best-effort plist uninstall. Returns the localized description
    /// of any throw so callers can fold it into their own `lastError`
    /// composition without making this a hard-failure step.
    func uninstallAgentArtifacts() async -> String? {
        do {
            try await installer.uninstall(label: agentMetadata.label)
            return nil
        } catch {
            logger.warning("plist uninstall failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}
