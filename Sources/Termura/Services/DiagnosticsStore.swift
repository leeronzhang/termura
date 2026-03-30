import Foundation
import Observation

/// Accumulates compiler and linter diagnostics extracted from completed OutputChunks.
///
/// Lifecycle: co-owned with `CommandRouter` inside `ProjectScope`. Both are released together
/// when the project window closes, so the `[weak self]` chunk handler becomes a no-op at that
/// point without requiring an explicit `tearDown()` call.
@Observable
@MainActor
final class DiagnosticsStore {

    // MARK: - State

    private(set) var items: [DiagnosticItem] = []

    var errorCount: Int { items.count(where: { $0.severity == .error }) }
    var warningCount: Int { items.count(where: { $0.severity == .warning }) }
    var hasProblems: Bool { !items.isEmpty }

    // @ObservationIgnored: internal lifecycle slot; views must never observe this.
    @ObservationIgnored private var chunkHandlerToken: UUID?

    private let projectRoot: String

    // MARK: - Init

    init(commandRouter: CommandRouter, projectRoot: String) {
        self.projectRoot = projectRoot
        chunkHandlerToken = commandRouter.onChunkCompleted { [weak self] chunk in
            self?.process(chunk: chunk)
        }
    }

    // MARK: - Mutation

    /// Removes all accumulated diagnostics.
    func clearAll() {
        items = []
    }

    // MARK: - Private

    private func process(chunk: OutputChunk) {
        let src = ProblemDetector.source(from: chunk.commandText)
        // Clear stale diagnostics from this session+source so a successful re-run
        // (exitCode == 0) results in an empty array from detect() → problems cleared.
        items.removeAll { $0.sessionID == chunk.sessionID && $0.source == src }
        let newItems = ProblemDetector.detect(from: chunk, projectRoot: projectRoot)
        guard !newItems.isEmpty else { return }
        let combined = items + newItems
        items = Array(combined.suffix(AppConfig.Diagnostics.maxTotalItems))
    }
}
