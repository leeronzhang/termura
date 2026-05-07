// PR8 §3.5 / §3.7 — classifies an inbound CloudKit envelope's
// `sourceDeviceId` (cloudSourceDeviceId domain) against the paired-
// device store. Returns enough domain-tagged identity material for
// the ingress to call `router.primeAuthenticatedChannel(...)` without
// re-running the handshake.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "TrustedSourceGate")

actor TrustedSourceGate {
    enum Classification: Sendable, Equatable {
        case knownActive(
            pairedDeviceId: UUID,
            cloudSourceDeviceId: UUID,
            negotiatedCodec: CodecKind,
            pairingId: UUID?
        )
        case knownRevoked(pairedDeviceId: UUID)
        case unknown
    }

    private let store: any PairedDeviceStore
    private let derive: @Sendable (Data) -> UUID

    init(
        store: any PairedDeviceStore,
        derive: @escaping @Sendable (Data) -> UUID = DeviceIdentity.deriveDeviceId(from:)
    ) {
        self.store = store
        self.derive = derive
    }

    /// `sourceDeviceId` is in the **cloudSourceDeviceId** domain — the
    /// public-key-derived id the iPhone uses on every CloudKit
    /// envelope. The match path is O(1) via the persisted field; the
    /// fallback re-derives from `publicKey` for legacy entries that
    /// pre-date PR8 and triggers a background backfill so the next
    /// classify call hits the fast path.
    func classify(sourceDeviceId: UUID) async -> Classification {
        let devices: [PairedDevice]
        do {
            devices = try await store.load()
        } catch {
            logger.warning("paired store load failed during classify: \(error.localizedDescription)")
            return .unknown
        }
        if let direct = devices.first(where: { $0.cloudSourceDeviceId == sourceDeviceId }) {
            return classification(for: direct)
        }
        // Legacy fallback — entry pre-dates PR8 and lacks the cached
        // field. Re-derive from publicKey, return classification, and
        // schedule a backfill so subsequent calls hit the fast path.
        for device in devices where device.cloudSourceDeviceId == nil {
            if derive(device.publicKey) == sourceDeviceId {
                Task { [store, derive] in
                    do {
                        try await store.backfillCloudSourceDeviceIdIfMissing(deriving: derive)
                    } catch {
                        logger.warning("background backfill failed: \(error.localizedDescription)")
                    }
                }
                return classification(for: device)
            }
        }
        return .unknown
    }

    private func classification(for device: PairedDevice) -> Classification {
        let cloudId = device.cloudSourceDeviceId ?? derive(device.publicKey)
        if device.isActive {
            return .knownActive(
                pairedDeviceId: device.id,
                cloudSourceDeviceId: cloudId,
                negotiatedCodec: device.negotiatedCodec,
                pairingId: device.pairingId
            )
        }
        return .knownRevoked(pairedDeviceId: device.id)
    }
}
