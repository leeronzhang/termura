import Foundation

enum RepositoryError: LocalizedError {
    case invalidID(String)
    case invalidColorLabel(String)
    case notFound(String)
    case compressionFailed
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidID(let id):
            return "Invalid record ID: \(id)"
        case .invalidColorLabel(let label):
            return "Invalid color label: \(label)"
        case .notFound(let id):
            return "Record not found: \(id)"
        case .compressionFailed:
            return "Data compression/decompression failed."
        case .migrationFailed(let detail):
            return "Database migration failed: \(detail)"
        }
    }
}
