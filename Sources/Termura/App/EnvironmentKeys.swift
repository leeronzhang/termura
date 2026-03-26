import SwiftUI

// MARK: - ThemeManager

@MainActor
private struct ThemeManagerKey: @preconcurrency EnvironmentKey {
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
