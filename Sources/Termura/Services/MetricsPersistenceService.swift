import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "MetricsPersistenceService")

// MARK: - Persisted data model

/// Codable mirror of HistogramStats for JSON serialization.
struct PersistedHistogramStats: Codable, Sendable {
    let count: Int
    let sum: Double
    let min: Double
    let max: Double
    let mean: Double?
    let p50: Double?
    let p95: Double?
    let p99: Double?
}

/// Codable snapshot with string-keyed dictionaries for JSON portability.
struct PersistedMetricsSnapshot: Codable, Sendable {
    let counters: [String: Int]
    let gauges: [String: Double]
    let histograms: [String: PersistedHistogramStats]

    init(from snapshot: MetricsSnapshot) {
        counters = Dictionary(
            uniqueKeysWithValues: snapshot.counters.map { ($0.key.rawValue, $0.value) }
        )
        gauges = Dictionary(
            uniqueKeysWithValues: snapshot.gauges.map { ($0.key.rawValue, $0.value) }
        )
        histograms = Dictionary(
            uniqueKeysWithValues: snapshot.histograms.map { key, stats in
                let persisted = PersistedHistogramStats(
                    count: stats.count, sum: stats.sum,
                    min: stats.min, max: stats.max,
                    mean: stats.mean,
                    p50: stats.p50, p95: stats.p95, p99: stats.p99
                )
                return (key.rawValue, persisted)
            }
        )
    }
}

/// A single on-disk metrics record, written at session end or app quit.
struct PersistedMetricsRecord: Codable, Sendable {
    let recordedAt: Date
    let sessionDurationSeconds: Double
    let snapshot: PersistedMetricsSnapshot
}

// MARK: - Actor

/// Persists session metrics to `~/.termura/metrics/` as timestamped JSON files.
///
/// Call `flush()` when a session ends or the app quits. Old records are automatically
/// rotated to keep at most `AppConfig.Metrics.persistedSessionCount` files on disk.
/// This enables post-hoc P99 SLO analysis across sessions.
actor MetricsPersistenceService {
    private let metrics: any MetricsCollectorProtocol
    private let metricsDirectory: URL
    private let sessionStartTime: ContinuousClock.Instant

    init(
        metrics: any MetricsCollectorProtocol,
        homeDirectory: URL = URL(fileURLWithPath: AppConfig.Paths.homeDirectory)
    ) {
        self.metrics = metrics
        self.sessionStartTime = ContinuousClock.now
        metricsDirectory = homeDirectory
            .appendingPathComponent(AppConfig.Persistence.directoryName)
            .appendingPathComponent(AppConfig.Metrics.metricsDirectoryName)
    }

    // MARK: - Public API

    /// Snapshots current metrics and writes a timestamped JSON record to disk,
    /// then rotates old files beyond `AppConfig.Metrics.persistedSessionCount`.
    func flush() async {
        let snap = await metrics.snapshot()
        let elapsed = (ContinuousClock.now - sessionStartTime).totalSeconds
        let record = PersistedMetricsRecord(
            recordedAt: Date(),
            sessionDurationSeconds: elapsed,
            snapshot: PersistedMetricsSnapshot(from: snap)
        )
        do {
            try ensureDirectoryExists()
            try writeRecord(record)
            try rotateOldFiles()
        } catch {
            logger.error("MetricsPersistenceService flush failed: \(error)")
        }
    }

    // MARK: - Private

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: metricsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func writeRecord(_ record: PersistedMetricsRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let filename = "metrics-\(isoFilenameTimestamp()).json"
        let url = metricsDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        logger.debug("MetricsPersistenceService wrote \(filename)")
    }

    private func rotateOldFiles() throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: metricsDirectory,
            includingPropertiesForKeys: nil
        )
        let records = contents
            .filter { $0.lastPathComponent.hasPrefix("metrics-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let excess = records.count - AppConfig.Metrics.persistedSessionCount
        guard excess > 0 else { return }
        for url in records.prefix(excess) {
            try FileManager.default.removeItem(at: url)
            logger.debug("MetricsPersistenceService rotated \(url.lastPathComponent)")
        }
    }

    /// Produces an ISO8601 timestamp safe for use as a filename (colons replaced with hyphens).
    private func isoFilenameTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}
