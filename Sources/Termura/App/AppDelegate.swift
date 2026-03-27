import AppKit
import KeyboardShortcuts
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "AppDelegate")

/// Dependency injection root. Owns global services and per-project contexts.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Global services (shared across all projects)

    let engineFactory: any TerminalEngineFactory
    let themeManager: ThemeManager
    let fontSettings: FontSettings
    let tokenCountingService: TokenCountingService
    let notificationService: NotificationService
    let menuBarService: MenuBarService
    let themeImportService: ThemeImportService
    let recentProjects: RecentProjectsService

    // MARK: - Project coordinator

    let projectCoordinator: ProjectCoordinator

    // MARK: - UI controllers

    var visorController: VisorWindowController?
    @Published var showShellOnboarding = false

    // MARK: - Init

    override init() {
        // Register bundled fonts FIRST, before any UI or FontSettings init.
        Self.registerBundledFonts()

        let factory: any TerminalEngineFactory = LiveTerminalEngineFactory()
        engineFactory = factory
        themeManager = ThemeManager()
        fontSettings = FontSettings()
        tokenCountingService = TokenCountingService()
        notificationService = NotificationService()
        menuBarService = MenuBarService()
        themeImportService = ThemeImportService()
        recentProjects = RecentProjectsService()
        projectCoordinator = ProjectCoordinator()

        super.init()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupVisorShortcut()
        checkShellIntegrationOnboarding()
        setupMenuBarActivation()
        projectCoordinator.start(with: ProjectCoordinator.Dependencies(
            engineFactory: engineFactory,
            tokenCountingService: tokenCountingService,
            themeManager: themeManager,
            fontSettings: fontSettings,
            notificationService: notificationService,
            menuBarService: menuBarService,
            recentProjects: recentProjects,
            windowChromeConfigurator: { [weak self] window in
                self?.configureProjectWindow(window)
            }
        ))
        logger.info("Termura launched")
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
        projectCoordinator.handleTermination()
    }

    func applicationWillTerminate(_ notification: Notification) {
        projectCoordinator.tearDown()
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
