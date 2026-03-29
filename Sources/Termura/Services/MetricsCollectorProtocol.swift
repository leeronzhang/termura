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

/// Aggregated stats for a single histogram metric.
/// Stores a fixed-capacity reservoir of the most-recent raw samples so that
/// P50/P95/P99 percentiles can be computed on demand.
struct HistogramEntry: Sendable {
    private(set) var count: Int = 0
    private(set) var sum: Double = 0
    private(set) var min: Double = .infinity
    private(set) var max: Double = -.infinity
    /// Ring buffer of the most recent N samples (N = AppConfig.Metrics.reservoirCapacity).
    private var samples: [Double] = []

    init() {
        samples.reserveCapacity(AppConfig.Metrics.reservoirCapacity)
    }

    mutating func record(_ value: Double) {
        count += 1
        sum += value
        if value < min { min = value }
        if value > max { max = value }
        // Evict oldest sample when reservoir is full.
        // Array.removeFirst() is O(n) for n=256 — negligible cost.
        if samples.count >= AppConfig.Metrics.reservoirCapacity {
            samples.removeFirst()
        }
        samples.append(value)
    }

    var mean: Double? { !samples.isEmpty ? sum / Double(count) : nil }

    /// Nearest-rank percentile over the reservoir window (proportion in 0.0–1.0).
    /// Returns nil when no samples have been recorded.
    func percentile(_ proportion: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let index = Swift.max(0, Int(ceil(proportion * Double(sorted.count))) - 1)
        return sorted[index]
    }
}

/// Derived statistics for a histogram metric, including reservoir-based percentiles.
/// Produced by `MetricsCollector.snapshot()` and carried in `MetricsSnapshot`.
struct HistogramStats: Sendable {
    let count: Int
    let sum: Double
    let min: Double
    let max: Double
    let mean: Double?
    let p50: Double?
    let p95: Double?
    let p99: Double?
}

/// Point-in-time snapshot of all recorded metrics.
/// Used by CrashContext, MetricsPersistenceService, and diagnostics.
struct MetricsSnapshot: Sendable {
    let counters: [MetricName: Int]
    let gauges: [MetricName: Double]
    /// Histogram statistics keyed by metric name, including percentiles.
    let histograms: [MetricName: HistogramStats]

    /// Backward-compatibility shim for callers that only need sample counts.
    /// Deprecated: prefer `histograms[name]?.count` for new code.
    var histogramCounts: [MetricName: Int] { histograms.mapValues(\.count) }
}

/// Protocol for metrics collection. All conformers must be actors for thread safety.
protocol MetricsCollectorProtocol: Actor {
    /// Increment a counter by the given value (default 1).
    func increment(_ name: MetricName, by value: Int)

    /// Record a measured duration for a histogram metric.
    func recordDuration(_ name: MetricName, seconds: Double)

    /// Set a gauge to a point-in-time value.
    func gauge(_ name: MetricName, value: Double)

    /// Return a snapshot of current metric values including histogram percentiles.
    func snapshot() -> MetricsSnapshot
}

/// Default parameter convenience.
extension MetricsCollectorProtocol {
    func increment(_ name: MetricName) {
        increment(name, by: 1)
    }
}
