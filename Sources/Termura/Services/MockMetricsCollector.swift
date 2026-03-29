import Foundation

#if DEBUG

/// Test mock for MetricsCollectorProtocol. Records all calls for assertion.
actor MockMetricsCollector: MetricsCollectorProtocol {
    private(set) var incrementCalls: [(MetricName, Int)] = []
    private(set) var durationCalls: [(MetricName, Double)] = []
    private(set) var gaugeCalls: [(MetricName, Double)] = []

    func increment(_ name: MetricName, by value: Int) {
        incrementCalls.append((name, value))
    }

    func recordDuration(_ name: MetricName, seconds: Double) {
        durationCalls.append((name, seconds))
    }

    func gauge(_ name: MetricName, value: Double) {
        gaugeCalls.append((name, value))
    }

    func snapshot() -> MetricsSnapshot {
        // Derive accumulated state from recorded calls so snapshot mirrors the real implementation.
        // Counters: cumulative sum of all increments per metric.
        var counters: [MetricName: Int] = [:]
        for (name, value) in incrementCalls {
            counters[name, default: 0] += value
        }
        // Gauges: last-write-wins, matching MetricsCollector semantics.
        var gauges: [MetricName: Double] = [:]
        for (name, value) in gaugeCalls {
            gauges[name] = value
        }
        // Histogram counts: one entry per recordDuration call.
        var histogramCounts: [MetricName: Int] = [:]
        for (name, _) in durationCalls {
            histogramCounts[name, default: 0] += 1
        }
        return MetricsSnapshot(counters: counters, gauges: gauges, histogramCounts: histogramCounts)
    }

    // MARK: - Test helpers

    func incrementCount(for name: MetricName) -> Int {
        incrementCalls.filter { $0.0 == name }.reduce(0) { $0 + $1.1 }
    }

    func hasDuration(for name: MetricName) -> Bool {
        durationCalls.contains { $0.0 == name }
    }
}

#endif
