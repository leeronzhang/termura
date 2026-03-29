import Foundation
import os
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "MetricsCollector")

/// Central metrics collection actor. Records counters, duration histograms, and gauges
/// using Apple-native `OSSignposter` for Instruments compatibility and `OSLog` for
/// structured logging.
///
/// Logging discipline:
/// - Per-event calls (`increment`, `recordDuration`, `gauge`) emit `.debug` only.
///   At `.debug` level, OSLog defers string evaluation — cost is ~100ns, acceptable on hot paths.
/// - A `.info`-level summary is written inside `snapshot()`, which is invoked intentionally
///   (crash context, diagnostics) rather than on every metric event.
/// - Signpost events in `recordDuration` use a single `emitEvent` call (not a zero-width
///   `beginInterval`/`endInterval` pair) because the duration is measured by the caller before
///   `recordDuration` is invoked.
actor MetricsCollector: MetricsCollectorProtocol {
    // MARK: - Signpost log

    private let signposter: OSSignposter

    // MARK: - Counter storage

    private var counters: [MetricName: Int] = [:]

    // MARK: - Gauge storage

    private var gauges: [MetricName: Double] = [:]

    // MARK: - Histogram storage (lightweight summary stats)

    private var histogramCounts: [MetricName: Int] = [:]
    private var histogramSums: [MetricName: Double] = [:]
    private var histogramMins: [MetricName: Double] = [:]
    private var histogramMaxes: [MetricName: Double] = [:]

    // MARK: - Init

    init() {
        signposter = OSSignposter(
            logger: Logger(subsystem: "com.termura.app", category: "Signpost")
        )
    }

    // MARK: - MetricsCollectorProtocol

    func increment(_ name: MetricName, by value: Int = 1) {
        counters[name, default: 0] += value
        logger.debug("metric.counter \(name.rawValue)=\(self.counters[name, default: 0])")
    }

    func recordDuration(_ name: MetricName, seconds: Double) {
        histogramCounts[name, default: 0] += 1
        histogramSums[name, default: 0] += seconds

        if let current = histogramMins[name] {
            histogramMins[name] = min(current, seconds)
        } else {
            histogramMins[name] = seconds
        }

        if let current = histogramMaxes[name] {
            histogramMaxes[name] = max(current, seconds)
        } else {
            histogramMaxes[name] = seconds
        }

        // Single emitEvent — correct for post-hoc duration recording where the measured
        // interval has already elapsed. A begin/end pair would create a zero-width span
        // with no timeline value.
        signposter.emitEvent("MetricDuration", "\(name.rawValue) \(seconds)s")

        logger.debug(
            "metric.histogram \(name.rawValue) duration=\(seconds, format: .fixed(precision: 4))s"
        )
    }

    func gauge(_ name: MetricName, value: Double) {
        gauges[name] = value
        logger.debug("metric.gauge \(name.rawValue)=\(value, format: .fixed(precision: 2))")
    }

    func snapshot() -> MetricsSnapshot {
        let snap = MetricsSnapshot(
            counters: counters,
            gauges: gauges,
            histogramCounts: histogramCounts
        )
        // Summary log at .info — called intentionally (crash context, diagnostics),
        // not on every metric event.
        logger.info(
            "metrics.snapshot counters=\(snap.counters.count) gauges=\(snap.gauges.count) histograms=\(snap.histogramCounts.count)"
        )
        return snap
    }
}
