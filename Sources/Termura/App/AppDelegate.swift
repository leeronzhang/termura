import AppKit
import KeyboardShortcuts
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "AppDelegate")

/// Dependency injection root. Owns the app-level service container and the project coordinator.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - App-level services

    let services: AppServices

    // MARK: - Project coordinator

    let projectCoordinator: ProjectCoordinator

    // MARK: - UI controllers

    var visorController: VisorWindowController?
    /// Stores the NSNotificationCenter tokens registered by `observeFullScreenTransitions`
    /// keyed by window identity. Prevents duplicate registration and enables cleanup on close.
    var fullScreenObserverTokens: [ObjectIdentifier: [any NSObjectProtocol]] = [:]

    // MARK: - Titlebar KVO guards

    /// KVO observation that reverts `titlebarAppearsTransparent` when AppKit resets it.
    var titlebarPropertyKVO: NSKeyValueObservation?
    /// KVO observations on individual NSVisualEffectViews inside the titlebar container.
    var titlebarEffectKVOObservers: [NSKeyValueObservation] = []
    /// Identities of effect views currently under KVO observation (avoids redundant reinstall).
    var titlebarEffectObservedViews: Set<ObjectIdentifier> = []

    // MARK: - Remote session push observer

    /// OWNER: this AppDelegate. CANCEL/TEARDOWN: `applicationWillTerminate`
    /// invokes `sessionListBroadcaster?.stop()`, which cancels the
    /// observation task and removes its NotificationCenter token.
    var sessionListBroadcaster: SessionListBroadcaster?

    // MARK: - Init

    override init() {
        // Register bundled fonts FIRST, before any UI or FontSettings init.
        Self.registerBundledFonts()

        let collector = MetricsCollector()
        let environment = ProcessInfo.processInfo.environment
        let shellInstaller = Self.makeShellInstaller(environment: environment)
        // Coordinator is needed before AppServices because the remote adapter closures
        // capture it weakly to resolve the active project's session store on demand.
        let coordinator = ProjectCoordinator()
        // Push seam: SessionListBroadcaster yields to this; harness router subscribes via adapter.
        let (sessionChangeStream, sessionChangeContinuation) = AsyncStream<Void>.makeStream()
        // Broadcaster constructed before the engine factory so the factory can hold a weak
        // ping-on-exit ref back to it. snapshotProvider routes through `gatherActiveSessions`
        // so engine-state changes (process exit) drive iOS list refreshes outside the
        // `withObservationTracking` graph.
        let broadcaster = SessionListBroadcaster(
            coordinator: coordinator,
            changeContinuation: sessionChangeContinuation,
            snapshotProvider: { [weak coordinator] in
                Self.gatherActiveSessions(coordinator: coordinator).map(\.id)
            }
        )
        let engineFactory = Self.makeEngineFactory(
            environment: environment,
            onEngineLifecycleChanged: { [weak broadcaster] in
                broadcaster?.pingNow()
            }
        )
        let remoteAdapter = Self.makeRemoteAdapter(
            coordinator: coordinator,
            changeStream: sessionChangeStream
        )
        let remoteIntegration = RemoteIntegrationLauncher.make(adapter: remoteAdapter)
        let remoteAgentBridge = RemoteIntegrationLauncher.makeAgentBridge(integration: remoteIntegration)
        services = AppServices(
            engineFactory: engineFactory,
            themeManager: ThemeManager(),
            fontSettings: FontSettings(),
            tokenCountingService: TokenCountingService(),
            notificationService: NotificationService(),
            menuBarService: MenuBarService(),
            themeImportService: ThemeImportService(),
            recentProjects: RecentProjectsService(),
            metricsCollector: collector,
            metricsPersistenceService: MetricsPersistenceService(metrics: collector),
            shellHookInstaller: shellInstaller,
            webViewPool: WebViewPool(),
            remoteSessionsAdapter: remoteAdapter,
            remoteIntegration: remoteIntegration,
            remoteControlController: RemoteControlController(
                integration: remoteIntegration,
                agentBridge: remoteAgentBridge,
                userDefaults: UserDefaults.standard
            ),
            remoteAgentBridge: remoteAgentBridge
        )
        projectCoordinator = coordinator
        sessionListBroadcaster = broadcaster

        super.init()
    }

    private static func makeEngineFactory(
        environment: [String: String],
        onEngineLifecycleChanged: @escaping @MainActor @Sendable () -> Void
    ) -> any TerminalEngineFactory {
        #if DEBUG
        if environment["UI_TESTING_MOCK_TERMINAL_ENGINE"] != nil {
            return DebugTerminalEngineFactory()
        }
        #endif
        return LiveTerminalEngineFactory(onEngineLifecycleChanged: onEngineLifecycleChanged)
    }

    private static func makeShellInstaller(environment: [String: String]) -> any ShellHookInstallerProtocol {
        // UI-testing: swap in a mock shell installer so tests never write to ~/.zshrc.
        #if DEBUG
        if environment["UI_TESTING_MOCK_SHELL_INSTALLER"] != nil {
            return DebugShellHookInstaller()
        }
        #endif
        return ShellHookInstaller()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        performApplicationDidFinishLaunching()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Secondary defense: re-suppress titlebar chrome on app activation.
        // AppKit resets titlebarAppearsTransparent and effect views when the app
        // regains focus; the KVO guard catches most resets, but re-applying here
        // covers any gap between the reset and the KVO callback.
        for window in NSApp.windows {
            guard !(window is NSPanel), window.contentViewController != nil,
                  !window.styleMask.contains(.fullScreen) else { continue }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            suppressTitlebarChrome(window)
            CATransaction.commit()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Include metrics flush in handleTermination's structured task group so it is
        // protected by the termination timeout (not fire-and-forget after the reply is sent).
        let persistence = services.metricsPersistenceService
        return projectCoordinator.handleTermination { await persistence.flush() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionListBroadcaster?.stop()
        Self.stopRemoteAgentBridge(services.remoteAgentBridge)
        projectCoordinator.tearDown()
        // Metrics flush is handled in applicationShouldTerminate's handleTermination task group.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Shoebox semantics: prefer un-hiding existing project windows so PTY
            // sessions stay attached. Only fall back to launcher (recents/picker)
            // when no hidden window is alive in memory.
            if !projectCoordinator.restoreHiddenWindows() {
                projectCoordinator.restoreLastProjectOrShowPicker()
            }
        }
        return true
    }

    // MARK: - Project management (delegated to ProjectCoordinator)

    func openProject(at url: URL) {
        projectCoordinator.openProject(at: url)
    }

    func showProjectPicker() {
        projectCoordinator.showProjectPicker()
    }

    /// The context of the most recently focused project window.
    var activeContext: ProjectContext? { projectCoordinator.activeContext }
}
