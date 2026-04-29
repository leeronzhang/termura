import Foundation
import Security

public actor KeychainPairedDeviceStore: PairedDeviceStore {
    private let serviceName: String
    private let account: String

    public init(serviceName: String, account: String = "paired-devices.v1") {
        self.serviceName = serviceName
        self.account = account
    }

    public func load() throws -> [PairedDevice] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw PairedDeviceStoreError.persistenceFailure(code: Int32(status))
        }
        guard let data = item as? Data else {
            throw PairedDeviceStoreError.decodingFailure
        }
        return try JSONDecoder().decode([PairedDevice].self, from: data)
    }

    public func add(_ device: PairedDevice) throws {
        var current = try load()
        current.removeAll { $0.id == device.id }
        current.append(device)
        try persist(current)
    }

    public func update(_ device: PairedDevice) throws {
        var current = try load()
        guard let index = current.firstIndex(where: { $0.id == device.id }) else {
            throw PairedDeviceStoreError.notFound(id: device.id)
        }
        current[index] = device
        try persist(current)
    }

    public func remove(id: UUID) throws {
        var current = try load()
        let initialCount = current.count
        current.removeAll { $0.id == id }
        guard current.count != initialCount else {
            throw PairedDeviceStoreError.notFound(id: id)
        }
        try persist(current)
    }

    public func backfillCloudSourceDeviceIdIfMissing(
        deriving derive: @Sendable (Data) -> UUID
    ) throws {
        var current = try load()
        var mutated = false
        for index in current.indices where current[index].cloudSourceDeviceId == nil {
            current[index].cloudSourceDeviceId = derive(current[index].publicKey)
            mutated = true
        }
        guard mutated else { return }
        try persist(current)
    }

    private func persist(_ devices: [PairedDevice]) throws {
        let encoded = try JSONEncoder().encode(devices)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: encoded,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw PairedDeviceStoreError.persistenceFailure(code: Int32(updateStatus))
        }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = encoded
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PairedDeviceStoreError.persistenceFailure(code: Int32(addStatus))
        }
    }
}
