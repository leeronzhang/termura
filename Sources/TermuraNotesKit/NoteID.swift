import Foundation

/// Type-safe wrapper around UUID for note identity.
public struct NoteID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        rawValue = UUID()
    }
}

extension NoteID: CustomStringConvertible {
    public var description: String { rawValue.uuidString }
}
