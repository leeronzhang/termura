import XCTest
@testable import Termura

/// XCTMetric-based performance tests validating SLO targets from CLAUDE.md.
///
/// Uses `measure(metrics:)` with `XCTClockMetric` for precise duration measurement,
/// complementing the existing PerformanceSLOTests with proper metrics instrumentation.
final class PerformanceXCTMetricTests: XCTestCase {
    // MARK: - Session switch < 100ms

    @MainActor
    func testSessionSwitchWithXCTMetric() throws {
        let factory = MockTerminalEngineFactory()
        let engineStore = TerminalEngineStore(factory: factory)
        let metricsCollector = MockMetricsCollector()
        let store = SessionStore(
            engineStore: engineStore,
            metricsCollector: metricsCollector
        )

        var ids: [SessionID] = []
        for i in 0 ..< 10 {
            let session = store.createSession(title: "Session \(i)")
            ids.append(session.id)
        }

        let options = XCTMeasureOptions.default
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric()], options: options) {
            for id in ids {
                store.activateSession(id: id)
            }
        }

        engineStore.terminateAll()
    }

    // MARK: - Full-text search < 200ms

    func testSearchLatencyWithXCTMetric() async throws {
        let sessionRepo = MockSessionRepository()
        let noteRepo = MockNoteRepository()

        // Seed data for realistic search
        for i in 0 ..< 20 {
            let record = SessionRecord(title: "Session \(i) with searchable content")
            try await sessionRepo.save(record)
        }

        let service = SearchService(sessionRepository: sessionRepo, noteRepository: noteRepo)

        let options = XCTMeasureOptions.default
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric()], options: options) {
            let expectation = expectation(description: "search")
            Task {
                _ = try await service.search(query: "searchable")
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: AppConfig.SLO.searchSeconds * 3)
        }
    }

    // MARK: - Output chunk append < 16ms (1 frame)

    @MainActor
    func testOutputAppendWithXCTMetric() {
        let sessionID = SessionID()
        let store = OutputStore(sessionID: sessionID)

        let options = XCTMeasureOptions.default
        options.iterationCount = 50

        measure(metrics: [XCTClockMetric()], options: options) {
            let chunk = OutputChunk(
                sessionID: sessionID,
                commandText: "echo hello",
                outputLines: (0 ..< 50).map { "output line \($0)" },
                rawANSI: String(repeating: "a", count: 2000),
                exitCode: 0,
                startedAt: Date(),
                finishedAt: Date()
            )
            store.append(chunk)
        }
    }

    // MARK: - Token estimation < 1ms

    func testTokenEstimationWithXCTMetric() async {
        let service = TokenCountingService()
        let sessionID = SessionID()
        let longText = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 1000)

        let options = XCTMeasureOptions.default
        options.iterationCount = 50

        measure(metrics: [XCTClockMetric()], options: options) {
            let expectation = expectation(description: "token")
            let sid = sessionID
            Task {
                await service.accumulateOutput(for: sid, text: longText)
                _ = await service.estimatedTokens(for: sid)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)
        }
    }

    // MARK: - ANSI stripping performance

    func testANSIStrippingWithXCTMetric() {
        // Build realistic ANSI-heavy output
        var ansiText = ""
        for i in 0 ..< 100 {
            ansiText += "\u{001B}[32mLine \(i): \u{001B}[0m some text \u{001B}[1;31mERROR\u{001B}[0m\n"
        }

        let options = XCTMeasureOptions.default
        options.iterationCount = 50

        measure(metrics: [XCTClockMetric()], options: options) {
            _ = ANSIStripper.strip(ansiText)
        }
    }

    // MARK: - MetricsCollector throughput

    func testMetricsCollectorThroughput() async {
        let collector = MetricsCollector()

        let options = XCTMeasureOptions.default
        options.iterationCount = 10

        measure(options: options) {
            let expectation = expectation(description: "metrics")
            Task {
                for _ in 0 ..< 1000 {
                    await collector.increment(.dbWrite)
                    await collector.recordDuration(.dbWriteDuration, seconds: 0.001)
                }
                _ = await collector.snapshot()
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }

    // MARK: - SLO config assertions

    func testSLOConfigValues() {
        // Verify SLO targets are set to expected values
        XCTAssertLessThanOrEqual(
            AppConfig.SLO.launchSeconds, 2.0,
            "Launch SLO should be <= 2s"
        )
        XCTAssertLessThanOrEqual(
            AppConfig.SLO.searchSeconds, 0.2,
            "Search SLO should be <= 200ms"
        )
        XCTAssertLessThanOrEqual(
            AppConfig.SLO.inputLatencySeconds, 0.016,
            "Input latency SLO should be <= 16ms"
        )
        XCTAssertLessThanOrEqual(
            AppConfig.Runtime.sessionSwitchDeadlineSeconds, 0.1,
            "Session switch deadline should be <= 100ms"
        )
    }
}
