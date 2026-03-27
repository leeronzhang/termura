import Foundation
import os
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "MetricsCollector")

/// Central metrics collection actor. Records counters, duration histograms, and gauges
/// using Apple-native `OSSignposter` for Instruments compatibility and `OSLog` for
/// structured logging.
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
        logger.info("metric.counter \(name.rawValue)=\(self.counters[name, default: 0])")
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

        // Emit signpost event for Instruments timeline
        let sid = signposter.makeSignpostID()
        let state = signposter.beginInterval("MetricDuration", id: sid, "\(name.rawValue)")
        signposter.endInterval("MetricDuration", state, "\(name.rawValue) \(seconds)s")

        let count = histogramCounts[name, default: 0]
        let avg = histogramSums[name, default: 0] / Double(count)
        let secFmt = String(format: "%.4f", seconds)
        let avgFmt = String(format: "%.4f", avg)
        logger.info("metric.histogram \(name.rawValue) duration=\(secFmt)s count=\(count) avg=\(avgFmt)s")
    }

    func gauge(_ name: MetricName, value: Double) {
        gauges[name] = value
        logger.info("metric.gauge \(name.rawValue)=\(value, format: .fixed(precision: 2))")
    }

    func snapshot() -> MetricsSnapshot {
        MetricsSnapshot(
            counters: counters,
            gauges: gauges,
            histogramCounts: histogramCounts
        )
    }
}
