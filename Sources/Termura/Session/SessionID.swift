import Foundation

/// Type-safe wrapper around UUID for session identity.
struct SessionID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    init() {
        rawValue = UUID()
    }
}

extension SessionID: CustomStringConvertible {
    var description: String { rawValue.uuidString }
}
