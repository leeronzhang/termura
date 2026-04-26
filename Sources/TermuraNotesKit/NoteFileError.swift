import Foundation

public enum NoteFileError: LocalizedError {
    case missingFrontmatter
    case missingRequiredField(String)
    case fileReadFailed(path: String, underlying: Error)
    case fileWriteFailed(path: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .missingFrontmatter:
            "Note file is missing YAML frontmatter delimiters (---)."
        case let .missingRequiredField(field):
            "Note frontmatter is missing required field: \(field)"
        case let .fileReadFailed(path, underlying):
            "Failed to read note file at \(path): \(underlying.localizedDescription)"
        case let .fileWriteFailed(path, underlying):
            "Failed to write note file at \(path): \(underlying.localizedDescription)"
        }
    }
}
