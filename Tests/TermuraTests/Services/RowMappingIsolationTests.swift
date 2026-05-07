import Foundation
import OSLog
@testable import Termura
import Testing

// Regression — a corrupt local-DB row used to make
// `try rows.map { try $0.toX() }` throw for the whole batch, hiding
// every sibling row behind one bad apple. The shared helper isolates
// per-row failures, logs them, and keeps the survivors.
@Suite("Sequence.compactIsolatedMap")
struct RowMappingIsolationTests {
    private static let logger = Logger(subsystem: "com.termura.tests", category: "RowMappingIsolation")

    private struct Stub: Equatable {
        let id: String
        let shouldThrow: Bool
    }

    private struct StubError: Error {}

    @Test("happy path: every row maps to a value")
    func happyPath() {
        let rows = [Stub(id: "a", shouldThrow: false), Stub(id: "b", shouldThrow: false)]
        let mapped: [String] = rows.compactIsolatedMap(
            logger: Self.logger,
            recordKind: "stub",
            rowID: { $0.id },
            transform: { $0.id.uppercased() }
        )
        #expect(mapped == ["A", "B"])
    }

    @Test("middle row throws: surrounding rows survive (poison-row isolation)")
    func middlePoisonSurvives() {
        let rows = [
            Stub(id: "a", shouldThrow: false),
            Stub(id: "poison", shouldThrow: true),
            Stub(id: "c", shouldThrow: false)
        ]
        let mapped: [String] = rows.compactIsolatedMap(
            logger: Self.logger,
            recordKind: "stub",
            rowID: { $0.id },
            transform: { row in
                if row.shouldThrow { throw StubError() }
                return row.id
            }
        )
        #expect(mapped == ["a", "c"],
                "Healthy rows must survive when a single sibling row throws")
    }

    @Test("first row throws: trailing rows still map")
    func leadingPoisonSurvives() {
        let rows = [
            Stub(id: "poison", shouldThrow: true),
            Stub(id: "x", shouldThrow: false)
        ]
        let mapped: [String] = rows.compactIsolatedMap(
            logger: Self.logger,
            recordKind: "stub",
            rowID: { $0.id },
            transform: { row in
                if row.shouldThrow { throw StubError() }
                return row.id
            }
        )
        #expect(mapped == ["x"])
    }

    @Test("all rows throw: returns empty (does not throw)")
    func allPoisonReturnsEmpty() {
        let rows = [Stub(id: "p1", shouldThrow: true), Stub(id: "p2", shouldThrow: true)]
        let mapped: [String] = rows.compactIsolatedMap(
            logger: Self.logger,
            recordKind: "stub",
            rowID: { $0.id },
            transform: { _ in throw StubError() }
        )
        #expect(mapped.isEmpty,
                "All-poison batch must not propagate; helper returns empty + logs")
    }

    @Test("rowID closure default: nil id is acceptable for callsites without a stable key")
    func nilRowIDAcceptable() {
        let rows = [Stub(id: "ok", shouldThrow: false)]
        let mapped: [String] = rows.compactIsolatedMap(
            logger: Self.logger,
            recordKind: "stub",
            transform: { $0.id }
        )
        #expect(mapped == ["ok"])
    }
}
