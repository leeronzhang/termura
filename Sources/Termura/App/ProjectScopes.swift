import Combine
import Foundation
import Observation

// Feature-scoped DI containers. Each scope groups related services
// so views declare only the dependencies they actually use.
// ProjectContext remains the composition root that creates these scopes;
// scopes are injected into the SwiftUI environment, not ProjectContext itself.

// MARK: - SessionScope

/// Core session lifecycle: store, terminal engines, agent state.
/// Used by views that display or manage sessions.
@Observable
@MainActor
final class SessionScope {
    let store: SessionStore
    let engines: TerminalEngineStore
    let agentStates: AgentStateStore

    init(
        store: SessionStore,
        engines: TerminalEngineStore,
        agentStates: AgentStateStore
    ) {
        self.store = store
        self.engines = engines
        self.agentStates = agentStates
    }
}

// MARK: - DataScope

/// Data-access services: repositories and search.
/// Used by views that query or display persisted data (sheets, harness, etc.).
@Observable
@MainActor
final class DataScope {
    let searchService: any SearchServiceProtocol
    /// Semantic vector search service. `nil` until a real Core ML embedding model is bundled;
    /// when nil the "Semantic" tab is hidden from the search UI.
    let vectorSearchService: (any VectorSearchServiceProtocol)?
    let ruleFileRepository: any RuleFileRepositoryProtocol
    let sessionMessageRepository: any SessionMessageRepositoryProtocol

    init(
        searchService: any SearchServiceProtocol,
        vectorSearchService: (any VectorSearchServiceProtocol)?,
        ruleFileRepository: any RuleFileRepositoryProtocol,
        sessionMessageRepository: any SessionMessageRepositoryProtocol
    ) {
        self.searchService = searchService
        self.vectorSearchService = vectorSearchService
        self.ruleFileRepository = ruleFileRepository
        self.sessionMessageRepository = sessionMessageRepository
    }
}

// MARK: - ProjectScope

/// Git and project file-tree services.
/// Used by views that display project structure or diffs.
@Observable
@MainActor
final class ProjectScope {
    let gitService: any GitServiceProtocol
    let viewModel: ProjectViewModel
    let diagnosticsStore: DiagnosticsStore

    init(
        gitService: any GitServiceProtocol,
        viewModel: ProjectViewModel,
        diagnosticsStore: DiagnosticsStore
    ) {
        self.gitService = gitService
        self.viewModel = viewModel
        self.diagnosticsStore = diagnosticsStore
    }
}
