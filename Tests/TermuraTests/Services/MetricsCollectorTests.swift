import Foundation
import Testing
@testable import Termura

@Suite("MetricsCollector")
struct MetricsCollectorTests {
    // MARK: - Counters

    @Test("Increment increases counter by default value of 1")
    func incrementDefault() async {
        let collector = MetricsCollector()
        await collector.increment(.sessionCreated)
        let snap = await collector.snapshot()
        #expect(snap.counters[.sessionCreated] == 1)
    }

    @Test("Increment increases counter by custom value")
    func incrementCustom() async {
        let collector = MetricsCollector()
        await collector.increment(.dbWrite, by: 5)
        let snap = await collector.snapshot()
        #expect(snap.counters[.dbWrite] == 5)
    }

    @Test("Multiple increments accumulate")
    func incrementAccumulates() async {
        let collector = MetricsCollector()
        await collector.increment(.sessionCreated)
        await collector.increment(.sessionCreated)
        await collector.increment(.sessionCreated, by: 3)
        let snap = await collector.snapshot()
        #expect(snap.counters[.sessionCreated] == 5)
    }

    // MARK: - Gauges

    @Test("Gauge sets point-in-time value")
    func gaugeSet() async {
        let collector = MetricsCollector()
        await collector.gauge(.activeSessions, value: 3.0)
        let snap = await collector.snapshot()
        #expect(snap.gauges[.activeSessions] == 3.0)
    }

    @Test("Gauge overwrites previous value")
    func gaugeOverwrite() async {
        let collector = MetricsCollector()
        await collector.gauge(.activeSessions, value: 3.0)
        await collector.gauge(.activeSessions, value: 1.0)
        let snap = await collector.snapshot()
        #expect(snap.gauges[.activeSessions] == 1.0)
    }

    // MARK: - Histograms

    @Test("recordDuration tracks count in histogram")
    func durationCount() async {
        let collector = MetricsCollector()
        await collector.recordDuration(.dbWriteDuration, seconds: 0.01)
        await collector.recordDuration(.dbWriteDuration, seconds: 0.02)
        let snap = await collector.snapshot()
        #expect(snap.histogramCounts[.dbWriteDuration] == 2)
    }

    @Test("recordDuration with single entry has correct count")
    func durationSingle() async {
        let collector = MetricsCollector()
        await collector.recordDuration(.searchDuration, seconds: 0.15)
        let snap = await collector.snapshot()
        #expect(snap.histogramCounts[.searchDuration] == 1)
    }

    // MARK: - Snapshot isolation

    @Test("Snapshot captures independent metric types")
    func snapshotIndependent() async {
        let collector = MetricsCollector()
        await collector.increment(.agentDetected)
        await collector.gauge(.activeAgents, value: 2.0)
        await collector.recordDuration(.launchDuration, seconds: 1.5)

        let snap = await collector.snapshot()
        #expect(snap.counters[.agentDetected] == 1)
        #expect(snap.gauges[.activeAgents] == 2.0)
        #expect(snap.histogramCounts[.launchDuration] == 1)
    }

    @Test("Empty snapshot has no entries")
    func snapshotEmpty() async {
        let collector = MetricsCollector()
        let snap = await collector.snapshot()
        #expect(snap.counters.isEmpty)
        #expect(snap.gauges.isEmpty)
        #expect(snap.histogramCounts.isEmpty)
    }

    // MARK: - Concurrent access

    @Test("Concurrent increments produce correct total")
    func concurrentIncrements() async {
        let collector = MetricsCollector()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    await collector.increment(.dbWrite)
                }
            }
        }
        let snap = await collector.snapshot()
        #expect(snap.counters[.dbWrite] == 100)
    }
}
