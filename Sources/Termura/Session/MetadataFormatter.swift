import Foundation

/// Pure formatting functions for session metadata display.
/// Extracted from SessionMetadataBarView to enable unit testing.
enum MetadataFormatter {
    /// Format token count: below 1000 as integer, above as "X.Xk".
    static func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1000 {
            return String(format: "%.1fk", Double(tokens) / 1000)
        }
        return "\(tokens)"
    }

    /// Abbreviate a directory path by replacing the home directory with "~".
    static func abbreviateDirectory(_ path: String) -> String {
        let home = AppConfig.Paths.homeDirectory
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Format estimated cost as a dollar string (e.g. "$0.42").
    static func formatCost(_ usd: Double) -> String {
        if usd < 0.01 {
            return String(format: "<$0.01")
        }
        return String(format: "$%.2f", usd)
    }

    /// Human-readable agent status text.
    static func formatAgentStatus(_ status: AgentStatus) -> String {
        switch status {
        case .idle: "Idle"
        case .thinking: "Thinking..."
        case .toolRunning: "Running tool..."
        case .waitingInput: "Waiting for input"
        case .error: "Error"
        case .completed: "Completed"
        }
    }

    /// Format session duration as human-readable string.
    static func formatDuration(_ duration: TimeInterval) -> String {
        let secs = Int(duration)
        let hours = secs / 3600
        let mins = (secs % 3600) / 60
        let remainSecs = secs % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else if mins > 0 {
            return "\(mins)m \(remainSecs)s"
        } else {
            return "\(remainSecs)s"
        }
    }
}
