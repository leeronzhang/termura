import Foundation

/// Named metrics used across the observability subsystem.
/// Grouped by instrument type: counters (monotonic), histograms (durations), gauges (point-in-time).
enum MetricName: String, Sendable {
    // MARK: - Counters (monotonic increment)

    case sessionCreated = "session.created"
    case sessionClosed = "session.closed"
    case dbWrite = "db.write"
    case dbRead = "db.read"
    case searchQuery = "search.query"
    case agentDetected = "agent.detected"

    // MARK: - Histograms (duration distributions)

    case dbWriteDuration = "db.write.duration"
    case dbReadDuration = "db.read.duration"
    case searchDuration = "search.duration"
    case sessionSwitchDuration = "session.switch.duration"
    case launchDuration = "launch.duration"
    case ptyStartDuration = "pty.start.duration"

    // MARK: - Gauges (point-in-time values)

    case activeSessions = "active.sessions"
    case activeAgents = "active.agents"
}

/// Point-in-time snapshot of all recorded metrics, used by CrashContext.
struct MetricsSnapshot: Sendable {
    let counters: [MetricName: Int]
    let gauges: [MetricName: Double]
    let histogramCounts: [MetricName: Int]
}

/// Protocol for metrics collection. All conformers are actors for thread safety.
protocol MetricsCollectorProtocol: Actor {
    /// Increment a counter by the given value (default 1).
    func increment(_ name: MetricName, by value: Int)

    /// Record a measured duration for a histogram metric.
    func recordDuration(_ name: MetricName, seconds: Double)

    /// Set a gauge to a point-in-time value.
    func gauge(_ name: MetricName, value: Double)

    /// Return a snapshot of current metric values.
    func snapshot() -> MetricsSnapshot
}

/// Default parameter convenience.
extension MetricsCollectorProtocol {
    func increment(_ name: MetricName) {
        increment(name, by: 1)
    }
}
