// Lookup / mutation surface invoked by `RemoteControlController`. Lives
// in its own file so `RemoteServerHarness.swift` stays under the 300-
// line file-length budget; the actor's `assembled` field and the
// `assembleIfNeeded()` helper are module-internal so this same-module
// extension can lazy-resolve the stack on first call.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteServerHarness+Lookup")

extension RemoteServerHarness {
    func issueInvitation() async throws -> PairingInvitation {
        let stack = try await assembleIfNeeded()
        return await stack.pairingService.beginPairing()
    }

    /// Forwards an APNs silent-push wake-up to the CloudKit transport so it
    /// polls the inbox immediately instead of waiting for the next tick.
    /// No-op if the server isn't running.
    func notifyPushReceived() async {
        guard isRunning, let stack = assembled, let cloudKit = stack.cloudKit else { return }
        await cloudKit.ingestPushNotification()
    }

    func listPairedDevices() async throws -> [PairedDeviceSummary] {
        let stack = try await assembleIfNeeded()
        let devices = try await stack.pairingService.listPairedDevices()
        return devices.map { device in
            PairedDeviceSummary(
                id: device.id,
                nickname: device.nickname,
                pairedAt: device.pairedAt,
                revokedAt: device.revokedAt
            )
        }
    }

    func revokePairedDevice(id: UUID) async throws {
        let stack = try await assembleIfNeeded()
        try await stack.pairingService.revoke(deviceId: id)
    }

    /// PR9 — bulk revoke. Returns the ids that were successfully marked
    /// `revokedAt`. Already-revoked entries are silently skipped (the
    /// underlying `PairingService.revokeAll` filters them by `isActive`
    /// before iterating). On per-device persistence failure the
    /// remaining entries still get processed and the failed ids surface
    /// as `RemoteAdapterError.partialRevokeAllFailed`, translated from
    /// the kit-internal `PairingError.revokeAllFailed` so the
    /// controller layer stays free of `TermuraRemoteServer` error
    /// types.
    func revokeAllPairedDevices() async throws -> [UUID] {
        let stack = try await assembleIfNeeded()
        do {
            return try await stack.pairingService.revokeAll()
        } catch let PairingError.revokeAllFailed(failed) {
            throw RemoteAdapterError.partialRevokeAllFailed(failed: failed)
        }
    }

    /// PR9 — resetPairings flow harness step 5a: drop every paired-
    /// device record and every persisted pair-key entry. After this
    /// returns, the harness has no surviving pairing state — but the
    /// long-lived `DeviceIdentity` keychain item, the audit log, and
    /// the agent-side cursor / quarantine stores are intentionally
    /// untouched here (cleared elsewhere or kept for a reason).
    /// Hard-failure semantics: if either store throws, the controller
    /// must abort reset and surface the error rather than continuing
    /// to step 5b.
    func resetPairingState() async throws {
        let stack = try await assembleIfNeeded()
        try await stack.pairingService.purgeAllPairings()
        try await stack.pairKeyStore.removeAll()
    }

    func auditLog() async throws -> [RemoteAuditEntry] {
        let stack = try await assembleIfNeeded()
        return await stack.auditLog.recent(limit: 500)
    }
}
