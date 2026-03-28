import SwiftUI

// MARK: - ThemeManager

@MainActor
private struct ThemeManagerKey: @preconcurrency EnvironmentKey {
    /// Placeholder default — production code must inject via `.environment(\.themeManager, ...)`.
    /// If a view reads this without injection, it gets an unconfigured ThemeManager.
    static let defaultValue = ThemeManager()
}

extension EnvironmentValues {
    var themeManager: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}

// MARK: - CommandRouter

@MainActor
private struct CommandRouterKey: @preconcurrency EnvironmentKey {
    /// Placeholder default — production code must inject via `.environment(\.commandRouter, ...)`.
    static let defaultValue = CommandRouter()
}

extension EnvironmentValues {
    var commandRouter: CommandRouter {
        get { self[CommandRouterKey.self] }
        set { self[CommandRouterKey.self] = newValue }
    }
}

// MARK: - FontSettings

@MainActor
private struct FontSettingsKey: @preconcurrency EnvironmentKey {
    /// Placeholder default — production code must inject via `.environment(\.fontSettings, ...)`.
    static let defaultValue = FontSettings()
}

extension EnvironmentValues {
    var fontSettings: FontSettings {
        get { self[FontSettingsKey.self] }
        set { self[FontSettingsKey.self] = newValue }
    }
}

// MARK: - NotesViewModel

@MainActor
private struct NotesViewModelKey: @preconcurrency EnvironmentKey {
    static let defaultValue = NotesViewModel(repository: MockNoteRepository())
}

extension EnvironmentValues {
    var notesViewModel: NotesViewModel {
        get { self[NotesViewModelKey.self] }
        set { self[NotesViewModelKey.self] = newValue }
    }
}

// MARK: - SessionScope

@MainActor
private struct SessionScopeKey: @preconcurrency EnvironmentKey {
    static let defaultValue = SessionScope(
        store: SessionStore(
            engineStore: TerminalEngineStore(factory: MockTerminalEngineFactory()),
            repository: MockSessionRepository()
        ),
        engines: TerminalEngineStore(factory: MockTerminalEngineFactory()),
        agentStates: AgentStateStore()
    )
}

extension EnvironmentValues {
    var sessionScope: SessionScope {
        get { self[SessionScopeKey.self] }
        set { self[SessionScopeKey.self] = newValue }
    }
}

// MARK: - DataScope

@MainActor
private struct DataScopeKey: @preconcurrency EnvironmentKey {
    static let defaultValue = DataScope(
        searchService: MockSearchService(),
        vectorSearchService: MockVectorSearchService(),
        ruleFileRepository: MockRuleFileRepository(),
        sessionMessageRepository: MockSessionMessageRepository()
    )
}

extension EnvironmentValues {
    var dataScope: DataScope {
        get { self[DataScopeKey.self] }
        set { self[DataScopeKey.self] = newValue }
    }
}

// MARK: - ProjectScope

@MainActor
private struct ProjectScopeKey: @preconcurrency EnvironmentKey {
    static let defaultValue = ProjectScope(
        gitService: MockGitService(),
        viewModel: ProjectViewModel(
            gitService: MockGitService(),
            projectRoot: "",
            commandRouter: CommandRouter()
        )
    )
}

extension EnvironmentValues {
    var projectScope: ProjectScope {
        get { self[ProjectScopeKey.self] }
        set { self[ProjectScopeKey.self] = newValue }
    }
}

// MARK: - SessionViewStateManager

@MainActor
private struct ViewStateManagerKey: @preconcurrency EnvironmentKey {
    static let defaultValue = SessionViewStateManager(
        commandRouter: CommandRouter(),
        sessionStore: SessionStore(
            engineStore: TerminalEngineStore(factory: MockTerminalEngineFactory()),
            repository: MockSessionRepository()
        ),
        tokenCountingService: MockTokenCountingService(),
        agentStateStore: AgentStateStore(),
        contextInjectionService: MockContextInjectionService(),
        sessionHandoffService: MockSessionHandoffService()
    )
}

extension EnvironmentValues {
    var viewStateManager: SessionViewStateManager {
        get { self[ViewStateManagerKey.self] }
        set { self[ViewStateManagerKey.self] = newValue }
    }
}
