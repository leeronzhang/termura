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

    // MARK: - Init

    override init() {
        // Register bundled fonts FIRST, before any UI or FontSettings init.
        Self.registerBundledFonts()

        let collector = MetricsCollector()
        let environment = ProcessInfo.processInfo.environment
        let engineFactory = Self.makeEngineFactory(environment: environment)
        let shellInstaller = Self.makeShellInstaller(environment: environment)
        // Coordinator is needed before AppServices because the remote adapter closures
        // capture it weakly to resolve the active project's session store on demand.
        let coordinator = ProjectCoordinator()
        let remoteAdapter = Self.makeRemoteAdapter(coordinator: coordinator)
        let remoteIntegration = RemoteIntegrationFactory.make(adapter: remoteAdapter)
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
            remoteControlController: RemoteControlController(integration: remoteIntegration)
        )
        projectCoordinator = coordinator

        super.init()
    }

    private static func makeEngineFactory(environment: [String: String]) -> any TerminalEngineFactory {
        #if DEBUG
        if environment["UI_TESTING_MOCK_TERMINAL_ENGINE"] != nil {
            return DebugTerminalEngineFactory()
        }
        #endif
        return LiveTerminalEngineFactory()
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

    private static func makeRemoteAdapter(coordinator: ProjectCoordinator) -> LiveRemoteSessionsAdapter {
        LiveRemoteSessionsAdapter(
            listProvider: { [weak coordinator] in
                Self.gatherActiveSessions(coordinator: coordinator)
            },
            commandRunner: { [weak coordinator] line, sessionId in
                try await Self.runRemoteCommand(coordinator: coordinator, line: line, sessionId: sessionId)
            }
        )
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchStart = ContinuousClock.now

        // Expose the app bundle path so spawned shells can find bundled CLIs (tn).
        setenv("TERMURA_APP_BUNDLE", Bundle.main.bundlePath, 1)

        // UI-testing: apply env-var overrides before any persistent state is read.
        let env = ProcessInfo.processInfo.environment
        if env["UI_TESTING_SKIP_SHELL_ONBOARDING"] != nil {
            UserDefaults.standard.set(true, forKey: AppConfig.ShellIntegration.installedDefaultsKey)
        }
        let launchProjectURL = env["UI_TESTING_PROJECT_PATH"].map { URL(fileURLWithPath: $0) }

        // Check for prior crash context
        if let priorCrash = CrashContext.loadPriorCrashContext() {
            logger.warning(
                "Prior crash context found: sessions=\(priorCrash.activeSessionCount) db=\(priorCrash.dbHealth)"
            )
        }
        CrashContext.clearPersistedData()
        Self.cleanStaleTempImages()

        // Pre-create a WKWebView for note rendering so the first Reading toggle is fast.
        services.webViewPool.preheat()

        setupVisorShortcut()
        setupMenuBarActivation()
        projectCoordinator.start(with: ProjectCoordinator.Dependencies(
            appServices: services,
            windowChromeConfigurator: { [weak self] window in
                self?.configureProjectWindow(window)
            },
            userDefaults: UserDefaults.standard,
            openOnLaunchURL: launchProjectURL
        ))
        logger.info("Termura launched")

        // Register for remote notifications so CloudKit silent pushes can wake
        // the remote-control transport. The handler `application(_:didReceiveRemoteNotification:)`
        // routes them into `services.remoteIntegration`; if remote control is
        // disabled, the integration's notify is a no-op (NullRemoteIntegration
        // or `isRunning == false` in the live harness).
        NSApp.registerForRemoteNotifications()

        let launchElapsed = ContinuousClock.now - launchStart
        let collector = services.metricsCollector
        Task { await collector.recordDuration(.launchDuration, seconds: launchElapsed.totalSeconds) }
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
        projectCoordinator.tearDown()
        // Metrics flush is handled in applicationShouldTerminate's handleTermination task group.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Restore last project or show picker if no windows are visible
            projectCoordinator.restoreLastProjectOrShowPicker()
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
