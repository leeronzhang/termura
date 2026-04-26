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
        let engineFactory: any TerminalEngineFactory
        #if DEBUG
        if environment["UI_TESTING_MOCK_TERMINAL_ENGINE"] != nil {
            engineFactory = DebugTerminalEngineFactory()
        } else {
            engineFactory = LiveTerminalEngineFactory()
        }
        #else
        engineFactory = LiveTerminalEngineFactory()
        #endif
        // UI-testing: swap in a mock shell installer so tests never write to ~/.zshrc.
        let shellInstaller: any ShellHookInstallerProtocol
        #if DEBUG
        if environment["UI_TESTING_MOCK_SHELL_INSTALLER"] != nil {
            shellInstaller = DebugShellHookInstaller()
        } else {
            shellInstaller = ShellHookInstaller()
        }
        #else
        shellInstaller = ShellHookInstaller()
        #endif
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
            webViewPool: WebViewPool()
        )
        projectCoordinator = ProjectCoordinator()

        super.init()
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

        let launchElapsed = ContinuousClock.now - launchStart
        let collector = services.metricsCollector
        Task { await collector.recordDuration(.launchDuration, seconds: launchElapsed.totalSeconds) }
    }

    /// Deletes PNG files in `~/.termura/tmp/` that are older than `AppConfig.DragDrop.staleImageAgeSeconds`.
    /// These files are created by drag-and-drop image operations in the terminal and editor. When the
    /// image is dropped, its path is pasted as shell text and the file is no longer tracked. The file
    /// must survive the current session (user may still be composing the command), but can safely be
    /// removed on the next launch. Runs off the main thread to avoid blocking startup.
    private static func cleanStaleTempImages() {
        // WHY: Startup cleanup must not block app launch on filesystem work.
        // OWNER: AppDelegate launches this detached task during app startup.
        // TEARDOWN: Fire-and-forget startup work; no retained handle is needed after one-shot cleanup completes.
        // TEST: Cover stale-file deletion and preservation of fresh temp images.
        Task.detached {
            let fm = FileManager.default
            let tmpDir = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(AppConfig.DragDrop.tempImageSubdirectory)
            guard fm.fileExists(atPath: tmpDir.path) else { return }
            let cutoff = Date().timeIntervalSinceReferenceDate - AppConfig.DragDrop.staleImageAgeSeconds
            do {
                let contents = try fm.contentsOfDirectory(
                    at: tmpDir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: .skipsHiddenFiles
                )
                for url in contents {
                    guard url.pathExtension == AppConfig.DragDrop.imagePasteExtension else { continue }
                    let attrs = try url.resourceValues(forKeys: [.contentModificationDateKey])
                    let modDate = attrs.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
                    guard modDate < cutoff else { continue }
                    do {
                        try fm.removeItem(at: url)
                        logger.debug("TempJanitor removed stale image: \(url.lastPathComponent)")
                    } catch {
                        logger.debug("TempJanitor could not remove \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            } catch {
                logger.debug("TempJanitor scan failed: \(error.localizedDescription)")
            }
        }
    }

    /// Explicitly register bundled fonts via CoreText.
    /// Called as a static method so it can run before `self` is fully initialized.
    /// `ATSApplicationFontsPath` in Info.plist is unreliable on some macOS versions.
    private static func registerBundledFonts() {
        // Xcode flattens Resources/Fonts/ into Resources/ at build time,
        // so search the resource directory directly for font files.
        guard let resourceURL = Bundle.main.resourceURL else {
            logger.warning("Bundle resource URL not found")
            return
        }
        let fm = FileManager.default
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: resourceURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            logger.warning("Could not list Resources directory: \(error)")
            return
        }
        var registered = 0
        for url in urls where url.pathExtension == "ttf" || url.pathExtension == "otf" {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                registered += 1
            } else {
                let desc = error?.takeRetainedValue().localizedDescription ?? "unknown"
                logger.debug("Font \(url.lastPathComponent) note: \(desc)")
            }
        }
        logger.info("Registered \(registered) bundled font(s)")
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
