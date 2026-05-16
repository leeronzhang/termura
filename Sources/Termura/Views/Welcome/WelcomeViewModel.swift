import AppKit
import Foundation
import Observation

/// State + intent surface for the cold-launch Welcome window.
///
/// Architecture: the ViewModel owns observable state and dispatches
/// to injected callbacks. It does not touch `NSWindow`, `NSOpenPanel`,
/// or the project coordinator directly — those concerns belong to
/// `WelcomeWindowController` (window lifecycle) and `ProjectLauncher`
/// (project opening side-effects). CLAUDE.md §3.1 / §3.2.
@Observable
@MainActor
final class WelcomeViewModel {
    /// Callbacks bundled into one struct so the View / Controller hand
    /// off exactly one parameter and the four flows stay symmetric.
    /// Every closure is `@MainActor`-isolated because callees mutate
    /// window state and the project coordinator; the struct itself is
    /// therefore not declared `Sendable` (it never crosses isolation).
    struct Actions {
        /// Open a previously visited project. Welcome window stays open
        /// until the callback signals success — the controller closes
        /// itself via `dismissRequested`.
        let openRecent: @MainActor (URL) -> Void
        /// Prompt the user for a parent directory + project name,
        /// create the directory, then open it as a project.
        let createNewProject: @MainActor () -> Void
        /// Prompt the user with `NSOpenPanel` and open the chosen
        /// directory as a project.
        let openExistingProject: @MainActor () -> Void
        /// User dismissed the window without choosing anything.
        let dismissRequested: @MainActor () -> Void
    }

    /// User-visible list of previously opened projects, most-recent first.
    private(set) var recents: [RecentProject]

    /// Short app version (e.g. "0.2.3"). Resolved at the composition
    /// root and handed to the view so SwiftUI never touches `Bundle.main`
    /// directly (CLAUDE.md §3.2).
    let appVersion: String

    /// Mirrors `AppConfig.UserDefaultsKeys.welcomeShowAtStartup`. The
    /// toggle in the Welcome footer writes through immediately so the
    /// preference takes effect at the very next cold launch.
    var showAtStartup: Bool {
        didSet {
            guard oldValue != showAtStartup else { return }
            userDefaults.set(showAtStartup, forKey: AppConfig.UserDefaultsKeys.welcomeShowAtStartup)
        }
    }

    private let recentProjects: RecentProjectsService
    private let userDefaults: any UserDefaultsStoring
    private let actions: Actions

    init(recentProjects: RecentProjectsService,
         userDefaults: any UserDefaultsStoring,
         appVersion: String,
         actions: Actions) {
        self.recentProjects = recentProjects
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        self.actions = actions
        recents = recentProjects.fetchRecent()
        // Absent key → first launch → default `true` so the user sees
        // the onboarding affordance at least once.
        if userDefaults.object(forKey: AppConfig.UserDefaultsKeys.welcomeShowAtStartup) == nil {
            showAtStartup = true
        } else {
            showAtStartup = userDefaults.bool(forKey: AppConfig.UserDefaultsKeys.welcomeShowAtStartup)
        }
    }

    // MARK: - Intents

    func openRecent(_ project: RecentProject) {
        let url = URL(fileURLWithPath: project.path)
        actions.openRecent(url)
    }

    func removeRecent(_ project: RecentProject) {
        recentProjects.removeRecent(URL(fileURLWithPath: project.path))
        recents = recentProjects.fetchRecent()
    }

    func createNewProject() {
        actions.createNewProject()
    }

    func openExistingProject() {
        actions.openExistingProject()
    }

    func userDismissed() {
        actions.dismissRequested()
    }

    /// Re-reads the recents file. Called by the controller every time
    /// the window becomes key so a fresh entry written by a sibling
    /// flow (e.g. URL-scheme open) shows up without restarting the app.
    func refreshRecents() {
        recents = recentProjects.fetchRecent()
    }
}
