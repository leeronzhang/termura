import SwiftUI

// MARK: - Mock Preview Context

//
// Centralises the mock objects that must be shared across EnvironmentKey defaults,
// mirroring the single-instance wiring in ProjectContext.open(at:).
//
// Rule: any two EnvironmentKey defaultValues whose real production counterparts
// share the same underlying object MUST reference the same instance here.
// Wiring source of truth: ProjectContext+Factory.swift makeScopes().
//
// Production code always injects real values via .environment(...).
// This context is only reached in Xcode Previews and unit tests that omit injection.
#if DEBUG
@MainActor
private enum MockPreviewContext {
    // Shared across SessionScopeKey and ViewStateManagerKey (matches makeScopes wiring).
    static let engineStore = TerminalEngineStore(factory: MockTerminalEngineFactory())
    static let agentStateStore = AgentStateStore()
    static let sessionStore = SessionStore(engineStore: engineStore, repository: MockSessionRepository())
    static let commandRouter = CommandRouter()
}
#endif

// MARK: - ThemeManager

private struct ThemeManagerKey: EnvironmentKey {
    /// Placeholder default -- production code must inject via `.environment(\.themeManager, ...)`.
    /// If a view reads this without injection, it gets an unconfigured ThemeManager.
    static let defaultValue: ThemeManager = MainActor.assumeIsolated { ThemeManager() }
}

extension EnvironmentValues {
    var themeManager: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}

// MARK: - CommandRouter

private struct CommandRouterKey: EnvironmentKey {
    /// Placeholder default -- production code must inject via `.environment(\.commandRouter, ...)`.
    static let defaultValue: CommandRouter = MainActor.assumeIsolated { CommandRouter() }
}

extension EnvironmentValues {
    var commandRouter: CommandRouter {
        get { self[CommandRouterKey.self] }
        set { self[CommandRouterKey.self] = newValue }
    }
}

// MARK: - FontSettings

private struct FontSettingsKey: EnvironmentKey {
    /// Placeholder default -- production code must inject via `.environment(\.fontSettings, ...)`.
    static let defaultValue: FontSettings = MainActor.assumeIsolated { FontSettings() }
}

extension EnvironmentValues {
    var fontSettings: FontSettings {
        get { self[FontSettingsKey.self] }
        set { self[FontSettingsKey.self] = newValue }
    }
}

// MARK: - NotesViewModel

private struct NotesViewModelKey: EnvironmentKey {
    #if DEBUG
    // Safe fallback for Previews/tests — production code must inject via `.environment(\.notesViewModel, ...)`.
    static let defaultValue: NotesViewModel = MainActor.assumeIsolated {
        NotesViewModel(repository: MockNoteRepository())
    }
    #else
    static let defaultValue: NotesViewModel = MainActor.assumeIsolated {
        NotesViewModel(repository: NullNoteRepository())
    }
    #endif
}

extension EnvironmentValues {
    var notesViewModel: NotesViewModel {
        get { self[NotesViewModelKey.self] }
        set { self[NotesViewModelKey.self] = newValue }
    }
}

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
        let engineStore = TerminalEngineStore(factory: MockTerminalEngineFactory())
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
            searchService: MockSearchService(),
            vectorSearchService: nil,
            ruleFileRepository: NullRuleFileRepository(),
            sessionMessageRepository: MockSessionMessageRepository()
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
        let gitService = MockGitService()
        let router = CommandRouter()
        return ProjectScope(
            gitService: gitService,
            viewModel: ProjectViewModel(
                gitService: gitService,
                projectRoot: "",
                commandRouter: router,
                fileTreeService: MockFileTreeService()
            ),
            diagnosticsStore: DiagnosticsStore(commandRouter: router, projectRoot: "")
        )
    }
    #else
    static let defaultValue: ProjectScope = MainActor.assumeIsolated {
        let gitService = NullGitService()
        let router = CommandRouter()
        return ProjectScope(
            gitService: gitService,
            viewModel: ProjectViewModel(gitService: gitService, projectRoot: ""),
            diagnosticsStore: DiagnosticsStore(commandRouter: router, projectRoot: "")
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
            tokenCountingService: MockTokenCountingService(),
            agentStateStore: MockPreviewContext.agentStateStore,
            contextInjectionService: MockContextInjectionService(),
            sessionHandoffService: MockSessionHandoffService()
        ))
    }
    #else
    static let defaultValue: SessionViewStateManager = MainActor.assumeIsolated {
        let engineStore = TerminalEngineStore(factory: MockTerminalEngineFactory())
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
