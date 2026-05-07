@testable import Termura
import XCTest

/// XCTMetric-based performance tests for Instruments baseline recording.
///
/// These tests record wall-clock baselines via XCTClockMetric. Hard SLO gates
/// (fail-on-violation) live in PerformanceSLOTests. The two concerns are kept
/// separate: baselines here, assertions there.
///
/// XCTest's measure(metrics:options:) is synchronous; there is no async variant.
/// Async operations are bridged via runAsync(_:timeout:), which uses
/// DispatchSemaphore, properly validates the timeout result, and propagates
/// errors — avoiding the silent-hang risk of the raw Task + semaphore pattern.
final class PerformanceXCTMetricTests: XCTestCase {
    // MARK: - Session switch < 100ms

    @MainActor
    func testSessionSwitchWithXCTMetric() async throws {
        let factory = MockTerminalEngineFactory()
        let engineStore = TerminalEngineStore(factory: factory)
        let metricsCollector = MockMetricsCollector()
        let store = SessionStore(
            engineStore: engineStore,
            repository: MockSessionRepository(),
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

        await engineStore.terminateAll()
    }

    // MARK: - Full-text search < 200ms

    func testSearchLatencyWithXCTMetric() async throws {
        let sessionRepo = MockSessionRepository()
        let noteRepo = MockNoteRepository()

        // Seed data so the filtering path executes meaningful work
        for i in 0 ..< 20 {
            try await sessionRepo.save(SessionRecord(title: "Session \(i) with searchable content"))
        }
        for i in 0 ..< 10 {
            try await noteRepo.save(NoteRecord(title: "Note \(i)", body: "searchable body \(i)"))
        }

        let service = SearchService(sessionRepository: sessionRepo, noteRepository: noteRepo)

        // Warm-up to exclude cold-start allocations from baseline
        _ = try await service.search(query: "searchable")

        let options = XCTMeasureOptions.default
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric()], options: options) {
            runAsync(timeout: AppConfig.SLO.searchSeconds * 20) {
                _ = try await service.search(query: "searchable")
            }
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

    // MARK: - Token estimation read path

    /// Measures the estimatedTokens() read path (O(1) actor property access).
    /// Accumulation is done once before the measure loop so each iteration
    /// reads a stable, pre-populated session rather than growing state.
    func testTokenEstimationWithXCTMetric() async {
        let service = TokenCountingService()
        let sessionID = SessionID()
        let longText = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 1000)

        // Pre-populate once; measure reads only
        await service.accumulateOutput(for: sessionID, text: longText)

        let options = XCTMeasureOptions.default
        options.iterationCount = 50

        // Generous timeout (10x frame budget) guards against hangs only
        measure(metrics: [XCTClockMetric()], options: options) {
            runAsync(timeout: AppConfig.SLO.inputLatencySeconds * 10) {
                _ = await service.estimatedTokens(for: sessionID)
            }
        }
    }

    // MARK: - ANSI stripping performance

    func testANSIStrippingWithXCTMetric() {
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

    func testMetricsCollectorThroughput() {
        let collector = MetricsCollector()

        let options = XCTMeasureOptions.default
        options.iterationCount = 10

        // 30s guards against complete hangs; 1000 increments should finish in < 100ms
        measure(options: options) {
            runAsync(timeout: 30.0) {
                for _ in 0 ..< 1000 {
                    await collector.increment(.dbWrite)
                    await collector.recordDuration(.dbWriteDuration, seconds: 0.001)
                }
                _ = await collector.snapshot()
            }
        }
    }

    // MARK: - SLO config assertions

    func testSLOConfigValues() {
        XCTAssertLessThanOrEqual(
            AppConfig.SLO.launchSeconds, 2.0,
            "Launch SLO should be <= 2s"
        )
        XCTAssertLessThanOrEqual(
            AppConfig.SLO.sessionSwitchSeconds, 0.1,
            "Session switch SLO should be <= 100ms"
        )
        XCTAssertLessThanOrEqual(
            AppConfig.SLO.searchSeconds, 0.2,
            "Search SLO should be <= 200ms"
        )
        XCTAssertLessThanOrEqual(
            AppConfig.SLO.inputLatencySeconds, 0.016,
            "Input latency SLO should be <= 16ms"
        )
    }
}

// MARK: - Async bridge helper

private extension PerformanceXCTMetricTests {
    /// Bridges async work into the synchronous measure() closure.
    ///
    /// DispatchSemaphore is the standard approach here because
    /// measure(metrics:options:) has no async variant in XCTest.
    /// Unlike raw Task + semaphore, this helper:
    ///   - validates the timeout result and calls XCTFail on hang
    ///   - captures and reports errors thrown by the async body
    func runAsync(
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: @Sendable @escaping () async throws -> Void
    ) {
        let sem = DispatchSemaphore(value: 0)
        // Capture file/line by value so the Task closure is @Sendable.
        // Error reporting happens inside the Task to avoid capturing mutable state.
        Task {
            do {
                try await body()
            } catch {
                XCTFail("Async operation threw: \(error)", file: file, line: line)
            }
            sem.signal()
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            XCTFail("Async operation timed out after \(timeout)s", file: file, line: line)
        }
    }
}
