import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AppDelegate.Launch")

extension AppDelegate {
    /// Bulk of `applicationDidFinishLaunching`. Pulled out of the main
    /// AppDelegate file so it stays under §6.1's 250-line soft cap.
    func performApplicationDidFinishLaunching() {
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
        // the remote-control transport.
        NSApp.registerForRemoteNotifications()

        // PR8 Phase 2 — kick off the agent ↔ app bridge. Free build is
        // a no-op; harness build constructs the XPC client + ingress.
        // PR10 Step 3 — fire `reinstallIfNeeded()` so a relaunch after
        // an app update / relocate silently re-aligns the on-disk plist
        // with the current `Termura.app` bundle. Skip when an env flag
        // is set so unit / UI tests can opt out of CloudKit / Keychain
        // side-effects during launch.
        if env["TERMURA_DISABLE_REMOTE_AGENT_BRIDGE"] == nil {
            Self.startRemoteAgentBridge(services.remoteAgentBridge)
            Self.scheduleReinstallIfNeeded(controller: services.remoteControlController)
            Self.restoreRemoteIntegration(controller: services.remoteControlController)
        }

        // Start broadcasting session-list changes to paired iOS clients.
        sessionListBroadcaster?.start()

        let launchElapsed = ContinuousClock.now - launchStart
        let collector = services.metricsCollector
        Task { await collector.recordDuration(.launchDuration, seconds: launchElapsed.totalSeconds) }
    }
}
