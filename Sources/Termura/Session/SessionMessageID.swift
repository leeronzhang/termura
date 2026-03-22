import Foundation

/// Type-safe wrapper around UUID for session message identity.
struct SessionMessageID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    init() {
        rawValue = UUID()
    }
}

extension SessionMessageID: CustomStringConvertible {
    var description: String { rawValue.uuidString }
}
