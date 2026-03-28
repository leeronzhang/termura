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
        MetricsSnapshot(counters: [:], gauges: [:], histogramCounts: [:])
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
