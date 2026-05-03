import Foundation

extension LaunchAgentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .plistEncodingFailed(reason):
            "Failed to encode LaunchAgent plist: \(reason)"
        case let .launchctlFailed(reason):
            "launchctl call failed: \(reason)"
        case let .fileWriteFailed(reason):
            "Failed to write LaunchAgent plist: \(reason)"
        }
    }
}
