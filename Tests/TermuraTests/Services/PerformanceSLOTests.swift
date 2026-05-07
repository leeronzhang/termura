@testable import Termura
import XCTest

/// Performance tests verifying CLAUDE.md SLO targets with hard XCTAssertLessThan gates.
/// Uses Date() timing so failures always report "SLO violated", not a timeout message.
final class PerformanceSLOTests: XCTestCase {
    // MARK: - Full-text search < 200ms (P99)

    func testSearchLatencyWithinSLO() async throws {
        let sessionRepo = MockSessionRepository()
        let noteRepo = MockNoteRepository()

        // Seed realistic data so the search path actually filters records
        for i in 0 ..< 50 {
            try await sessionRepo.save(SessionRecord(title: "Session \(i) searchable content"))
        }
        for i in 0 ..< 20 {
            try await noteRepo.save(NoteRecord(title: "Note \(i)", body: "searchable body text \(i)"))
        }
        let service = SearchService(sessionRepository: sessionRepo, noteRepository: noteRepo)

        // Warm-up: exclude cold-start allocations from the measured window
        _ = try await service.search(query: "searchable")

        let start = Date()
        _ = try await service.search(query: "searchable")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(
            elapsed,
            AppConfig.SLO.searchSeconds,
            "Search took \(String(format: "%.1f", elapsed * 1000))ms, " +
                "exceeds \(AppConfig.SLO.searchSeconds * 1000)ms SLO"
        )
    }

    // MARK: - Buffer Capacity Under Stress

    @MainActor
    func testOutputStoreCapacityUnderStress() {
        let store = OutputStore(sessionID: SessionID(), capacity: 500)
        for idx in 0 ..< 1000 {
            let chunk = OutputChunk(
                sessionID: SessionID(),
                commandText: "cmd\(idx)",
                outputLines: ["line"],
                rawANSI: "line",
                exitCode: 0,
                startedAt: Date(),
                finishedAt: Date()
            )
            store.append(chunk)
        }
        XCTAssertEqual(store.chunks.count, 500)
        // Oldest should be evicted; first remaining is cmd500
        XCTAssertEqual(store.chunks.first?.commandText, "cmd500")
    }

    // MARK: - SLO Threshold Assertions (fail if measured time exceeds target)

    /// Session switch must complete in < 100ms per switch on average.
    @MainActor
    func testSessionSwitchMeetsThreshold() async {
        let factory = MockTerminalEngineFactory()
        let engineStore = TerminalEngineStore(factory: factory)
        let store = SessionStore(engineStore: engineStore, repository: MockSessionRepository())

        var ids: [SessionID] = []
        for i in 0 ..< 10 {
            let session = store.createSession(title: "SLO Session \(i)")
            ids.append(session.id)
        }

        let start = Date()
        for id in ids {
            store.activateSession(id: id)
        }
        let totalSeconds = Date().timeIntervalSince(start)
        let averageSeconds = totalSeconds / Double(ids.count)

        XCTAssertLessThan(
            averageSeconds,
            AppConfig.SLO.sessionSwitchSeconds,
            "Session switch average \(String(format: "%.1f", averageSeconds * 1000))ms " +
                "exceeds \(AppConfig.SLO.sessionSwitchSeconds * 1000)ms SLO"
        )
        await engineStore.terminateAll()
    }

    /// Single OutputStore append must complete in < 16ms (1 frame).
    @MainActor
    func testOutputAppendMeetsThreshold() {
        let store = OutputStore(sessionID: SessionID())
        let chunk = OutputChunk(
            sessionID: SessionID(),
            commandText: "echo hello",
            outputLines: (0 ..< 100).map { "line \($0)" },
            rawANSI: String(repeating: "a", count: 5000),
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )
        let start = Date()
        store.append(chunk)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(
            elapsed,
            AppConfig.SLO.inputLatencySeconds,
            "OutputStore.append took \(String(format: "%.2f", elapsed * 1000))ms, " +
                "exceeds \(AppConfig.SLO.inputLatencySeconds * 1000)ms frame budget"
        )
    }

    /// Token estimation read must complete within one frame budget (16ms).
    /// Bug fix: uses a single SessionID so accumulate and estimatedTokens share the same session.
    func testTokenEstimationSLO() async {
        let service = TokenCountingService()
        let sessionID = SessionID()
        let longText = String(repeating: "The quick brown fox jumps. ", count: 10000)

        // Pre-populate so estimatedTokens has real accumulated data to return
        await service.accumulateOutput(for: sessionID, text: longText)

        // Warm-up to exclude actor-initialization cost
        _ = await service.estimatedTokens(for: sessionID)

        let start = Date()
        _ = await service.estimatedTokens(for: sessionID)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(
            elapsed,
            AppConfig.SLO.inputLatencySeconds,
            "Token estimation took \(String(format: "%.2f", elapsed * 1000))ms, " +
                "exceeds \(AppConfig.SLO.inputLatencySeconds * 1000)ms frame budget"
        )
    }

    // MARK: - ANSI strip SLO

    /// ANSIStripper.strip must process ~100KB of terminal output within one frame (16ms).
    func testANSIStripSLOFor100KB() {
        // Realistic ANSI-colored line: ~110 chars with SGR sequences.
        let line = "\u{1B}[1m\u{1B}[32mCompiling source file TargetModule/SomeFile.swift\u{1B}[0m output done\n"
        let input = String(repeating: line, count: 1000) // ~110KB
        _ = ANSIStripper.strip(input) // warm-up: exclude first-run allocations
        let start = Date()
        _ = ANSIStripper.strip(input)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(
            elapsed,
            AppConfig.SLO.inputLatencySeconds,
            "ANSIStripper.strip 100KB took \(String(format: "%.2f", elapsed * 1000))ms, " +
                "exceeds \(AppConfig.SLO.inputLatencySeconds * 1000)ms SLO"
        )
    }

    // MARK: - Config SLO Value Assertions

    func testConfigValuesMatchSLOTargets() {
        XCTAssertEqual(AppConfig.Terminal.maxScrollbackLines, 10000)
        XCTAssertEqual(AppConfig.Output.maxChunksPerSession, 500)
        XCTAssertLessThanOrEqual(AppConfig.SLO.searchSeconds, 0.2)
        XCTAssertLessThanOrEqual(AppConfig.SLO.sessionSwitchSeconds, 0.1)
    }
}
