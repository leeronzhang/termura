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
enum MockPreviewContext {
    // Shared across SessionScopeKey and ViewStateManagerKey (matches makeScopes wiring).
    static let engineStore = TerminalEngineStore(factory: DebugTerminalEngineFactory())
    static let agentStateStore = AgentStateStore()
    static let sessionStore = SessionStore(engineStore: engineStore, repository: DebugSessionRepository())
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
        NotesViewModel(repository: DebugNoteRepository())
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
