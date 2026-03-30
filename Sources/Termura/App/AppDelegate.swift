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

    // MARK: - Init

    override init() {
        // Register bundled fonts FIRST, before any UI or FontSettings init.
        Self.registerBundledFonts()

        let collector = MetricsCollector()
        services = AppServices(
            engineFactory: LiveTerminalEngineFactory(),
            themeManager: ThemeManager(),
            fontSettings: FontSettings(),
            tokenCountingService: TokenCountingService(),
            notificationService: NotificationService(),
            menuBarService: MenuBarService(),
            themeImportService: ThemeImportService(),
            recentProjects: RecentProjectsService(),
            metricsCollector: collector,
            metricsPersistenceService: MetricsPersistenceService(metrics: collector),
            shellHookInstaller: ShellHookInstaller()
        )
        projectCoordinator = ProjectCoordinator()

        super.init()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchStart = ContinuousClock.now

        // Check for prior crash context
        if let priorCrash = CrashContext.loadPriorCrashContext() {
            logger.warning(
                "Prior crash context found: sessions=\(priorCrash.activeSessionCount) db=\(priorCrash.dbHealth)"
            )
        }
        CrashContext.clearPersistedData()
        Self.cleanStaleTempImages()

        setupVisorShortcut()
        setupMenuBarActivation()
        projectCoordinator.start(with: ProjectCoordinator.Dependencies(
            appServices: services,
            windowChromeConfigurator: { [weak self] window in
                self?.configureProjectWindow(window)
            }
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
