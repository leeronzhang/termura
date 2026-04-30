import Foundation
import TermuraRemoteProtocol

public struct PairedDevice: Sendable, Codable, Equatable, Identifiable {
    /// Business id — UUID generated at pair time. Stable per-pair; surfaced
    /// in Settings UI, audit log device-id field, and the router's
    /// `.authenticated(deviceId:)` channel state. **Domain: paired-device
    /// records.** Distinct from `cloudSourceDeviceId` below — see PR8 §3.1.
    public let id: UUID
    public let nickname: String
    public let publicKey: Data
    public let pairedAt: Date
    public var revokedAt: Date?
    /// PR8 — codec the two peers agreed on during `handlePairInit`.
    /// Persisted on the device record so a fresh main-app process (e.g. one
    /// woken by the agent over XPC) can rebuild the router's per-channel
    /// `phases[channelId] = .active(<codec>)` without re-running the
    /// handshake. Decoded with `decodeIfPresent` so legacy v1 entries keep
    /// loading; missing field defaults to `.json`, the conservative codec
    /// both sides always understand.
    public var negotiatedCodec: CodecKind
    /// PR8 — pair-key id paired with this device. The agent ingress needs
    /// it to address the right `PairKey` when opening cipher payloads.
    /// Optional only for entries created before PR8; new entries always
    /// populate it inside `PairingService.completePairing`.
    public var pairingId: UUID?
    /// PR8 — `DeviceIdentity.deriveDeviceId(from: publicKey)` cached as a
    /// persisted field. **Domain: cloud-source device id.** This is what
    /// the router's `channels` map keys on, what CloudKit envelope records
    /// use for `sourceDeviceId`, and what the agent forwards as
    /// `AgentMailboxItem.sourceDeviceId`. Pure function of `publicKey` —
    /// caching it here avoids re-hashing on every trusted-source lookup
    /// and gives `TrustedSourceGate` an O(1) reverse map. Optional only
    /// for legacy entries created before PR8 landed; the migration path
    /// (`backfillCloudSourceDeviceIdIfMissing`) populates it on first
    /// read.
    public var cloudSourceDeviceId: UUID?

    public init(
        id: UUID = UUID(),
        nickname: String,
        publicKey: Data,
        pairedAt: Date,
        revokedAt: Date? = nil,
        negotiatedCodec: CodecKind = .json,
        pairingId: UUID? = nil,
        cloudSourceDeviceId: UUID? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.publicKey = publicKey
        self.pairedAt = pairedAt
        self.revokedAt = revokedAt
        self.negotiatedCodec = negotiatedCodec
        self.pairingId = pairingId
        self.cloudSourceDeviceId = cloudSourceDeviceId
    }

    public var isActive: Bool { revokedAt == nil }

    private enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case publicKey
        case pairedAt
        case revokedAt
        case negotiatedCodec
        case pairingId
        case cloudSourceDeviceId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.nickname = try container.decode(String.self, forKey: .nickname)
        self.publicKey = try container.decode(Data.self, forKey: .publicKey)
        self.pairedAt = try container.decode(Date.self, forKey: .pairedAt)
        self.revokedAt = try container.decodeIfPresent(Date.self, forKey: .revokedAt)
        self.negotiatedCodec = try container.decodeIfPresent(CodecKind.self, forKey: .negotiatedCodec) ?? .json
        self.pairingId = try container.decodeIfPresent(UUID.self, forKey: .pairingId)
        self.cloudSourceDeviceId = try container.decodeIfPresent(UUID.self, forKey: .cloudSourceDeviceId)
    }
}

public protocol PairedDeviceStore: Sendable {
    func load() async throws -> [PairedDevice]
    func add(_ device: PairedDevice) async throws
    func update(_ device: PairedDevice) async throws
    func remove(id: UUID) async throws
    /// PR9 — wipes every entry. Used by `PairingService.purgeAllPairings`
    /// in the resetPairings flow. Idempotent: calling on an empty store
    /// is a no-op (no thrown error).
    func removeAll() async throws
    /// PR8 — fills in `cloudSourceDeviceId` on every legacy entry whose
    /// field is `nil`, deriving the value from the persisted `publicKey`.
    /// New entries already populate the field at pair time, so calling
    /// this on a fully-migrated store is a no-op.
    ///
    /// `derive` is injected (rather than calling `DeviceIdentity` here)
    /// to keep the protocol package-agnostic: the protocol module doesn't
    /// import `TermuraRemoteProtocol` for transitive reasons, and the
    /// derivation function is the only behaviour the store actually
    /// needs.
    func backfillCloudSourceDeviceIdIfMissing(
        deriving derive: @Sendable (Data) -> UUID
    ) async throws
}

public actor InMemoryPairedDeviceStore: PairedDeviceStore {
    private var devices: [UUID: PairedDevice] = [:]

    public init(seed: [PairedDevice] = []) {
        for device in seed {
            devices[device.id] = device
        }
    }

    public func load() -> [PairedDevice] {
        Array(devices.values).sorted { $0.pairedAt < $1.pairedAt }
    }

    public func add(_ device: PairedDevice) {
        devices[device.id] = device
    }

    public func update(_ device: PairedDevice) throws {
        guard devices[device.id] != nil else {
            throw PairedDeviceStoreError.notFound(id: device.id)
        }
        devices[device.id] = device
    }

    public func remove(id: UUID) throws {
        guard devices.removeValue(forKey: id) != nil else {
            throw PairedDeviceStoreError.notFound(id: id)
        }
    }

    public func removeAll() {
        devices.removeAll()
    }

    public func backfillCloudSourceDeviceIdIfMissing(
        deriving derive: @Sendable (Data) -> UUID
    ) {
        for (key, device) in devices where device.cloudSourceDeviceId == nil {
            var updated = device
            updated.cloudSourceDeviceId = derive(device.publicKey)
            devices[key] = updated
        }
    }
}

public enum PairedDeviceStoreError: Error, Sendable, Equatable {
    case notFound(id: UUID)
    case persistenceFailure(code: Int32)
    case decodingFailure
}
