import SwiftUI

// MARK: - SessionScope

private struct SessionScopeKey: EnvironmentKey {
    #if DEBUG
    // Safe fallback for Previews/tests — production code must inject via `.environment(\.sessionScope, ...)`.
    // Shared objects come from MockPreviewContext so that SessionScopeKey and
    // ViewStateManagerKey see the same SessionStore / AgentStateStore, matching
    // the single-instance wiring in ProjectContext+Factory.swift makeScopes().
    static let defaultValue: SessionScope = MainActor.assumeIsolated {
        SessionScope(
            store: MockPreviewContext.sessionStore,
            engines: MockPreviewContext.engineStore,
            agentStates: MockPreviewContext.agentStateStore
        )
    }
    #else
    static let defaultValue: SessionScope = MainActor.assumeIsolated {
        let engineStore = TerminalEngineStore(factory: LiveTerminalEngineFactory())
        let store = SessionStore(engineStore: engineStore, repository: NullSessionRepository())
        return SessionScope(store: store, engines: engineStore, agentStates: AgentStateStore())
    }
    #endif
}

extension EnvironmentValues {
    var sessionScope: SessionScope {
        get { self[SessionScopeKey.self] }
        set { self[SessionScopeKey.self] = newValue }
    }
}

// MARK: - DataScope

private struct DataScopeKey: EnvironmentKey {
    #if DEBUG
    // Safe fallback for Previews/tests — production code must inject via `.environment(\.dataScope, ...)`.
    static let defaultValue: DataScope = MainActor.assumeIsolated {
        DataScope(
            searchService: DebugSearchService(),
            vectorSearchService: nil,
            ruleFileRepository: NullRuleFileRepository(),
            sessionMessageRepository: DebugSessionMessageRepository()
        )
    }
    #else
    static let defaultValue: DataScope = MainActor.assumeIsolated {
        DataScope(
            searchService: NullSearchService(),
            vectorSearchService: nil,
            ruleFileRepository: NullRuleFileRepository(),
            sessionMessageRepository: NullSessionMessageRepository()
        )
    }
    #endif
}

extension EnvironmentValues {
    var dataScope: DataScope {
        get { self[DataScopeKey.self] }
        set { self[DataScopeKey.self] = newValue }
    }
}

// MARK: - ProjectScope

private struct ProjectScopeKey: EnvironmentKey {
    #if DEBUG
    // Safe fallback for Previews/tests — production code must inject via `.environment(\.projectScope, ...)`.
    // gitService is shared between ProjectScope and ProjectViewModel so that
    // both see the same mock state in previews and tests.
    static let defaultValue: ProjectScope = MainActor.assumeIsolated {
        let gitService = DebugGitService()
        let router = CommandRouter()
        return ProjectScope(
            gitService: gitService,
            viewModel: ProjectViewModel(
                gitService: gitService,
                projectRoot: "",
                commandRouter: router,
                fileTreeService: DebugFileTreeService()
            ),
            diagnosticsStore: DiagnosticsStore(commandRouter: router, projectRoot: ""),
            aiCommitService: AICommitService(
                runner: CLIProcessRunner(),
                shellEnv: StaticUserShellEnvironment(path: ""),
                gitService: gitService
            )
        )
    }
    #else
    static let defaultValue: ProjectScope = MainActor.assumeIsolated {
        let gitService = NullGitService()
        let router = CommandRouter()
        return ProjectScope(
            gitService: gitService,
            viewModel: ProjectViewModel(gitService: gitService, projectRoot: ""),
            diagnosticsStore: DiagnosticsStore(commandRouter: router, projectRoot: ""),
            aiCommitService: AICommitService(
                runner: CLIProcessRunner(),
                shellEnv: StaticUserShellEnvironment(path: ""),
                gitService: gitService
            )
        )
    }
    #endif
}

extension EnvironmentValues {
    var projectScope: ProjectScope {
        get { self[ProjectScopeKey.self] }
        set { self[ProjectScopeKey.self] = newValue }
    }
}

// MARK: - SessionViewStateManager

private struct ViewStateManagerKey: EnvironmentKey {
    #if DEBUG
    // Safe fallback for Previews/tests — production code must inject via `.environment(\.viewStateManager, ...)`.
    // sessionStore and agentStateStore come from MockPreviewContext so they match
    // the instances in SessionScopeKey, mirroring production wiring in makeScopes().
    static let defaultValue: SessionViewStateManager = MainActor.assumeIsolated {
        SessionViewStateManager(.init(
            commandRouter: MockPreviewContext.commandRouter,
            sessionStore: MockPreviewContext.sessionStore,
            tokenCountingService: DebugTokenCountingService(),
            agentStateStore: MockPreviewContext.agentStateStore,
            contextInjectionService: DebugContextInjectionService(),
            sessionHandoffService: DebugSessionHandoffService()
        ))
    }
    #else
    static let defaultValue: SessionViewStateManager = MainActor.assumeIsolated {
        let engineStore = TerminalEngineStore(factory: LiveTerminalEngineFactory())
        let store = SessionStore(engineStore: engineStore, repository: NullSessionRepository())
        return SessionViewStateManager(.init(
            commandRouter: CommandRouter(),
            sessionStore: store,
            tokenCountingService: NullTokenCountingService(),
            agentStateStore: AgentStateStore(),
            contextInjectionService: NullContextInjectionService(),
            sessionHandoffService: NullSessionHandoffService()
        ))
    }
    #endif
}

extension EnvironmentValues {
    var viewStateManager: SessionViewStateManager {
        get { self[ViewStateManagerKey.self] }
        set { self[ViewStateManagerKey.self] = newValue }
    }
}
