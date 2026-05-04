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
    /// Persists session metrics to ~/.termura/metrics/ for cross-session SLO analysis.
    let metricsPersistenceService: MetricsPersistenceService
    let shellHookInstaller: any ShellHookInstallerProtocol
    /// Shared WKWebView pool for note rendering. Preheated at app launch.
    let webViewPool: any WebViewPoolProtocol
    /// Bridges the iOS remote-control feature to the active project's session store.
    /// Always present; falls back to `NullRemoteSessionsAdapter` when unused.
    let remoteSessionsAdapter: any RemoteSessionsAdapter
    /// Remote-control server. `NullRemoteIntegration` in Free build; real
    /// implementation from the paid harness when `HARNESS_ENABLED`. Lifecycle
    /// controlled via Settings UI.
    let remoteIntegration: any RemoteIntegration
    /// SwiftUI-bindable wrapper over `remoteIntegration`. Owned at the app
    /// scope so the Settings window can re-open without losing state.
    let remoteControlController: RemoteControlController
    /// PR8 Phase 2 — agent ↔ app bridge lifecycle. Free build:
    /// `NullRemoteAgentBridgeLifecycle` (no-op). Harness build: a
    /// concrete impl wired by `RemoteIntegrationLauncher.makeAgentBridge`
    /// that owns the XPC client + ingress + auto-connector. Call sites
    /// only see the protocol surface (no harness concrete types leak
    /// into the open-core repo).
    let remoteAgentBridge: any RemoteAgentBridgeLifecycle
}
