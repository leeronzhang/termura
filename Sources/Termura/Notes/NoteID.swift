import Foundation

/// Type-safe wrapper around UUID for note identity.
struct NoteID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    init() {
        rawValue = UUID()
    }
}

extension NoteID: CustomStringConvertible {
    var description: String { rawValue.uuidString }
}
