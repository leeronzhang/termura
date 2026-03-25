import Foundation

enum RepositoryError: LocalizedError {
    /// A record ID could not be parsed or is malformed.
    case invalidID(rawValue: String, entity: String)
    /// The color label string doesn't map to a known label.
    case invalidColorLabel(rawValue: String)
    /// The branch type string doesn't map to a known type.
    case invalidBranchType(rawValue: String)
    /// No record exists for the given identifier.
    case notFound(entity: String, id: String)
    /// Data compression or decompression failed.
    case compressionFailed
    /// A database migration step failed.
    case migrationFailed(version: String, underlying: Error?)
    /// The session tree exceeds the configured maximum depth.
    case branchDepthExceeded(currentDepth: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidID(rawValue, entity):
            "Invalid \(entity) ID: \(rawValue)"
        case let .invalidColorLabel(rawValue):
            "Invalid color label: \(rawValue)"
        case let .invalidBranchType(rawValue):
            "Invalid branch type: \(rawValue)"
        case let .notFound(entity, id):
            "\(entity) not found: \(id)"
        case .compressionFailed:
            "Data compression/decompression failed."
        case let .migrationFailed(version, underlying):
            "Database migration failed at \(version)\(underlying.map { ": \($0.localizedDescription)" } ?? "")"
        case let .branchDepthExceeded(depth):
            "Session tree depth \(depth) exceeds maximum (\(AppConfig.SessionTree.maxDepth))."
        }
    }

    /// Whether this error is recoverable by the user (e.g., retrying with valid input).
    var isRecoverable: Bool {
        switch self {
        case .invalidID, .invalidColorLabel, .invalidBranchType:
            true // Caller can correct the input.
        case .notFound, .compressionFailed, .migrationFailed, .branchDepthExceeded:
            false
        }
    }
}
