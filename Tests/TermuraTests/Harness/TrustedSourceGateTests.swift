#if HARNESS_ENABLED
import Foundation
@testable import Termura
import Testing
import TermuraRemoteProtocol
@testable import TermuraRemoteServer

@Suite("TrustedSourceGate.classify")
struct TrustedSourceGateTests {
    private static func makeDevice(
        publicKey: Data,
        cloudId: UUID? = nil,
        revoked: Bool = false
    ) -> PairedDevice {
        PairedDevice(
            nickname: "iPhone",
            publicKey: publicKey,
            pairedAt: Date(timeIntervalSince1970: 1_000),
            revokedAt: revoked ? Date(timeIntervalSince1970: 5_000) : nil,
            negotiatedCodec: .messagepack,
            pairingId: UUID(),
            cloudSourceDeviceId: cloudId
        )
    }

    @Test("knownActive when sourceDeviceId matches persisted cloudSourceDeviceId")
    func knownActiveOnMatch() async {
        let identity = DeviceIdentity.generate()
        let cloudId = DeviceIdentity.deriveDeviceId(from: identity.publicKeyData)
        let device = Self.makeDevice(publicKey: identity.publicKeyData, cloudId: cloudId)
        let store = InMemoryPairedDeviceStore(seed: [device])
        let gate = TrustedSourceGate(store: store)
        let result = await gate.classify(sourceDeviceId: cloudId)
        if case let .knownActive(pairedId, cloudSourceId, codec, pairingId) = result {
            #expect(pairedId == device.id)
            #expect(cloudSourceId == cloudId)
            #expect(codec == .messagepack)
            #expect(pairingId == device.pairingId)
            #expect(pairedId != cloudSourceId, "domains stay separate even on match")
        } else {
            Issue.record("expected .knownActive, got \(result)")
        }
    }

    @Test("legacy entry without cloudSourceDeviceId falls back to publicKey derivation")
    func fallbackForLegacyEntry() async {
        let identity = DeviceIdentity.generate()
        let cloudId = DeviceIdentity.deriveDeviceId(from: identity.publicKeyData)
        let legacy = Self.makeDevice(publicKey: identity.publicKeyData, cloudId: nil)
        let store = InMemoryPairedDeviceStore(seed: [legacy])
        let gate = TrustedSourceGate(store: store)
        let result = await gate.classify(sourceDeviceId: cloudId)
        if case .knownActive = result {
            // pass
        } else {
            Issue.record("legacy fallback should still return knownActive, got \(result)")
        }
    }

    @Test("revoked device classifies as knownRevoked")
    func revokedDevice() async {
        let identity = DeviceIdentity.generate()
        let cloudId = DeviceIdentity.deriveDeviceId(from: identity.publicKeyData)
        let device = Self.makeDevice(publicKey: identity.publicKeyData, cloudId: cloudId, revoked: true)
        let store = InMemoryPairedDeviceStore(seed: [device])
        let gate = TrustedSourceGate(store: store)
        let result = await gate.classify(sourceDeviceId: cloudId)
        if case let .knownRevoked(pairedId) = result {
            #expect(pairedId == device.id)
        } else {
            Issue.record("expected .knownRevoked, got \(result)")
        }
    }

    @Test("unknown source returns .unknown")
    func unknownSource() async {
        let store = InMemoryPairedDeviceStore()
        let gate = TrustedSourceGate(store: store)
        let result = await gate.classify(sourceDeviceId: UUID())
        #expect(result == .unknown)
    }
}
#endif
