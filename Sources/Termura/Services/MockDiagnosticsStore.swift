import Foundation
import Observation

#if DEBUG

/// Test double for DiagnosticsStore. Mirrors the same observable properties
/// without subscribing to CommandRouter — caller drives state via `inject(_:)`.
///
/// Follows the same pattern as MockSessionStore / MockAgentStateStore.
/// Protocol not required: stores use concrete @Observable types per CLAUDE.md §9.
@Observable
@MainActor
final class MockDiagnosticsStore {

    // MARK: - State (mirrors DiagnosticsStore)

    private(set) var items: [DiagnosticItem] = []

    var errorCount: Int { items.count(where: { $0.severity == .error }) }
    var warningCount: Int { items.count(where: { $0.severity == .warning }) }
    var hasProblems: Bool { !items.isEmpty }

    // MARK: - Test helpers

    /// Replaces the current item list, simulating diagnostics arriving from a chunk.
    func inject(_ newItems: [DiagnosticItem]) {
        items = newItems
    }

    /// Clears all items, mirroring DiagnosticsStore.clearAll().
    func clearAll() {
        items = []
    }
}

#endif
