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
        // Mirror production reservoir cap: evict oldest sample when full.
        if durationCalls.count(where: { $0.0 == name }) >= AppConfig.Metrics.reservoirCapacity {
            if let idx = durationCalls.firstIndex(where: { $0.0 == name }) {
                durationCalls.remove(at: idx)
            }
        }
        durationCalls.append((name, seconds))
    }

    func gauge(_ name: MetricName, value: Double) {
        gaugeCalls.append((name, value))
    }

    func snapshot() -> MetricsSnapshot {
        MetricsSnapshot(
            counters: buildCounters(),
            gauges: buildGauges(),
            histograms: buildHistograms()
        )
    }

    private func buildCounters() -> [MetricName: Int] {
        // Counters: cumulative sum of all increments per metric.
        var counters: [MetricName: Int] = [:]
        for (name, value) in incrementCalls {
            counters[name, default: 0] += value
        }
        return counters
    }

    private func buildGauges() -> [MetricName: Double] {
        // Gauges: last-write-wins, matching MetricsCollector semantics.
        var gauges: [MetricName: Double] = [:]
        for (name, value) in gaugeCalls {
            gauges[name] = value
        }
        return gauges
    }

    private func buildHistograms() -> [MetricName: HistogramStats] {
        // Local accumulator struct avoids a large-tuple lint violation.
        struct DurationBucket {
            var count: Int; var sum: Double; var minVal: Double; var maxVal: Double; var samples: [Double]
        }
        var buckets: [MetricName: DurationBucket] = [:]
        for (name, value) in durationCalls {
            if var b = buckets[name] {
                b.count += 1; b.sum += value
                if value < b.minVal { b.minVal = value }
                if value > b.maxVal { b.maxVal = value }
                b.samples.append(value); buckets[name] = b
            } else {
                buckets[name] = DurationBucket(count: 1, sum: value, minVal: value, maxVal: value, samples: [value])
            }
        }
        return buckets.mapValues { bucket in
            let sorted = bucket.samples.sorted()
            func pct(_ proportion: Double) -> Double? {
                guard !sorted.isEmpty else { return nil }
                return sorted[Swift.max(0, Int(ceil(proportion * Double(sorted.count))) - 1)]
            }
            return HistogramStats(
                count: bucket.count, sum: bucket.sum,
                min: bucket.minVal, max: bucket.maxVal,
                mean: bucket.sum / Double(bucket.count),
                p50: pct(0.50), p95: pct(0.95), p99: pct(0.99)
            )
        }
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
