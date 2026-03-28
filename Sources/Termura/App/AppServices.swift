import Foundation

/// Application-scope service container. Groups all global services that are
/// shared across projects and owned for the lifetime of the app.
///
/// Created once in `AppDelegate.init()` and passed as a unit to `ProjectCoordinator`.
/// This is NOT a singleton — it is a plain value type threaded through the DI chain.
/// Adding a new global service requires a change in exactly one place (here + the init).
struct AppServices {
    let engineFactory: any TerminalEngineFactory
    let themeManager: ThemeManager
    let fontSettings: FontSettings
    let tokenCountingService: TokenCountingService
    let notificationService: NotificationService
    let menuBarService: MenuBarService
    let themeImportService: ThemeImportService
    let recentProjects: RecentProjectsService
    let metricsCollector: any MetricsCollectorProtocol
}
