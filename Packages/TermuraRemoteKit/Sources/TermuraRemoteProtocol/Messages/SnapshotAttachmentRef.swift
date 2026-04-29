import Foundation

public struct SnapshotAttachmentRef: Sendable, Codable, Equatable {
    public enum Storage: String, Sendable, Codable, Equatable {
        case localFile = "local_file"
        case cloudKitAsset = "cloudkit_asset"
    }

    public let storage: Storage
    public let identifier: String
    public let byteCount: Int
    public let sha256Hex: String

    public init(storage: Storage, identifier: String, byteCount: Int, sha256Hex: String) {
        self.storage = storage
        self.identifier = identifier
        self.byteCount = byteCount
        self.sha256Hex = sha256Hex
    }
}
