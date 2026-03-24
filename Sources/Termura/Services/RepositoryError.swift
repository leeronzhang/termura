import Foundation

enum RepositoryError: LocalizedError {
    case invalidID(String)
    case invalidColorLabel(String)
    case invalidBranchType(String)
    case notFound(String)
    case compressionFailed
    case migrationFailed(String)
    case branchDepthExceeded

    var errorDescription: String? {
        switch self {
        case let .invalidID(id):
            "Invalid record ID: \(id)"
        case let .invalidColorLabel(label):
            "Invalid color label: \(label)"
        case let .invalidBranchType(type):
            "Invalid branch type: \(type)"
        case let .notFound(id):
            "Record not found: \(id)"
        case .compressionFailed:
            "Data compression/decompression failed."
        case let .migrationFailed(detail):
            "Database migration failed: \(detail)"
        case .branchDepthExceeded:
            "Session tree depth exceeds maximum (\(AppConfig.SessionTree.maxDepth))."
        }
    }
}
