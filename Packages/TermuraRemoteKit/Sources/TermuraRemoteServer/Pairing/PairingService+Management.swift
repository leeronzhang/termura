import Foundation
import TermuraRemoteProtocol

// PairingService surface that doesn't drive the live handshake — codec
// negotiation, paired-device queries, revocation, and reset. Lives in
// its own file to keep `PairingService.swift` under the file_length
// budget; the actor's stored properties (`store`, `pairKeyStore`,
// `clock`, `supportedCodecs`) and the private helper `activeDevice`
// are module-internal so this same-module extension can reach them
// without a public surface change.

public extension PairingService {
    func negotiateCodec(remoteSupported: [CodecKind]) -> CodecKind {
        CodecKind.negotiate(local: supportedCodecs, remote: remoteSupported)
    }

    /// Test / harness diagnostic surface — reads the persisted PairKey
    /// so callers can verify both sides arrived at the same secret. Not
    /// invoked from any production transport in PR7.
    func storedPairKey(forPairing id: UUID) async throws -> PairKey? {
        try await pairKeyStore.key(forPairing: id)
    }

    /// PR8 — persists the codec the two peers agreed on during the pair
    /// handshake plus the `pairingId` that addresses the symmetric
    /// `PairKey`. Called by the router immediately after `pairComplete`
    /// is queued; both fields are then available to a fresh main-app
    /// process (e.g. one woken by the agent over XPC) without re-running
    /// the handshake.
    ///
    /// `pairedDeviceId` is the paired-device store's primary key —
    /// the UUID owned by the `PairedDevice.id` domain, **not** the
    /// public-key-derived `cloudSourceDeviceId`. The two domains are
    /// kept distinct so the router's `channels[channelId]` map (keyed
    /// on `cloudSourceDeviceId`) can never accidentally collide with
    /// the store's `update(_:)` API (keyed on `id`). See PR8 §3.4.
    func recordNegotiation(
        pairedDeviceId: UUID,
        negotiatedCodec: CodecKind,
        pairingId: UUID
    ) async throws {
        var devices = try await store.load()
        guard let index = devices.firstIndex(where: { $0.id == pairedDeviceId }) else {
            throw PairedDeviceStoreError.notFound(id: pairedDeviceId)
        }
        devices[index].negotiatedCodec = negotiatedCodec
        devices[index].pairingId = pairingId
        try await store.update(devices[index])
    }

    func revoke(deviceId: UUID) async throws {
        var devices = try await store.load()
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else {
            throw PairedDeviceStoreError.notFound(id: deviceId)
        }
        // PR9 — re-revoking a device must not overwrite the original
        // `revokedAt`. UI races (double-tap, queued action) and the
        // upcoming `revokeAll` flow can both land here for an entry
        // that's already inactive; preserving the first revocation
        // timestamp keeps the audit trail meaningful.
        if devices[index].revokedAt != nil { return }
        devices[index].revokedAt = clock()
        try await store.update(devices[index])
    }

    /// PR9 — marks every active device as revoked at `clock()`. Returns
    /// the ids that were successfully revoked. Already-revoked entries
    /// are silently skipped (they're not in the success list because
    /// nothing changed). On per-device persistence failure the work
    /// continues for the remaining ids and the failed ids are surfaced
    /// via `PairingError.revokeAllFailed`.
    func revokeAll() async throws -> [UUID] {
        let now = clock()
        let devices = try await store.load()
        var succeeded: [UUID] = []
        var failed: [UUID] = []
        for device in devices where device.isActive {
            var copy = device
            copy.revokedAt = now
            do {
                try await store.update(copy)
                succeeded.append(device.id)
            } catch {
                failed.append(device.id)
            }
        }
        if !failed.isEmpty {
            throw PairingError.revokeAllFailed(failed: failed)
        }
        return succeeded
    }

    /// PR9 — drops every paired-device record from the store and resets
    /// any in-flight pairing handshake state. Used by the resetPairings
    /// flow in the harness; after `purgeAllPairings` returns, no past
    /// pairing — active or revoked — survives. Identity, pair keys, and
    /// audit log are out of scope here (cleared elsewhere).
    func purgeAllPairings() async throws {
        try await store.removeAll()
        clearPendingState()
        lastCompletedPairingIdValue = nil
    }

    func listPairedDevices() async throws -> [PairedDevice] {
        try await store.load()
    }

    func isPaired(publicKey: Data) async throws -> Bool {
        try await activeDevice(matchingPublicKey: publicKey) != nil
    }
}
