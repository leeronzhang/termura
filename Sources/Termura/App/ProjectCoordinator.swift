import AppKit
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectCoordinator")

/// Manages project window lifecycle: open, close, focus tracking, and termination handoff.
/// Extracted from AppDelegate to keep the composition root free of business logic.
@MainActor
final class ProjectCoordinator {
    /// Maps project URL to its window controller. Each window owns one project.
    private(set) var projectWindows: [URL: ProjectWindowController] = [:]

    /// The context of the most recently focused project window.
    private(set) var activeContext: ProjectContext?

    // MARK: - Injected dependencies (set via start())

    /// Groups all dependencies needed by ProjectCoordinator.
    struct Dependencies {
        let appServices: AppServices
        let windowChromeConfigurator: (NSWindow) -> Void
        let userDefaults: any UserDefaultsStoring
        /// When set, opens this URL on launch (skips picker + history). NOT added to recents.
        /// Use cases: UI tests with temp dirs, URL-scheme "open project" deep links.
        var openOnLaunchURL: URL?  // Optional: UI testing / URL-scheme deep link
    }

    private var deps: Dependencies?
    private var windowObserver: NSObjectProtocol?
    /// Tracks the chunk-handler token per open project so it can be removed on close.
    private var chunkHandlerTokens: [URL: UUID] = [:]
    /// Single-flight guard: URLs currently being opened. Prevents concurrent
    /// openProject calls from creating duplicate contexts during the async window.
    private var openingInFlight: Set<URL> = []
    /// Fired exactly once with the first project's CommandRouter after its window opens.
    /// Set by AppDelegate to perform launch-time work that requires a live CommandRouter.
    var onFirstProjectOpened: ((CommandRouter) -> Void)?

    // MARK: - Lifecycle

    /// Called once from `applicationDidFinishLaunching` to wire up dependencies and open projects.
    func start(with dependencies: Dependencies) {
        deps = dependencies
        observeWindowFocus()
        restoreLastProjectOrShowPicker()
    }

    // MARK: - Project management

    func openProject(at url: URL) {
        guard deps != nil else {
            logger.error("ProjectCoordinator not started before openProject call")
            return
        }
        if let existing = projectWindows[url] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard !openingInFlight.contains(url) else { return }
        openingInFlight.insert(url)
        // Task inherits @MainActor — DB migration in DatabaseService.init runs off main thread.
        Task { [weak self] in await self?.performOpenProjectAsync(url: url) }
    }

    private func performOpenProjectAsync(url: URL, persist: Bool = true) async {
        defer { openingInFlight.remove(url) }
        guard let deps else { return }
        // Re-check inside task — a concurrent open for the same URL may have completed.
        if let existing = projectWindows[url] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        do {
            let context = try await ProjectContext.open(
                at: url,
                engineFactory: deps.appServices.engineFactory,
                tokenCountingService: deps.appServices.tokenCountingService,
                metricsCollector: deps.appServices.metricsCollector,
                notificationService: deps.appServices.notificationService
            )
            let controller = ProjectWindowController(
                projectContext: context,
                themeManager: deps.appServices.themeManager,
                fontSettings: deps.appServices.fontSettings
            )
            projectWindows[url] = controller
            activeContext = context
            controller.onWindowClose = { [weak self] in self?.closeProject(at: url) }
            // Fire the launch-time callback exactly once after the first window opens.
            if projectWindows.count == 1 {
                onFirstProjectOpened?(context.commandRouter)
                onFirstProjectOpened = nil
            }
            if persist { deps.appServices.recentProjects.addRecent(url) }
            chunkHandlerTokens[url] = setupChunkHandler(for: context)
            if persist { persistOpenProjects() }
            controller.showWindow(nil)
            if let window = controller.window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                deps.windowChromeConfigurator(window)
            }
            controller.restoreFullScreenIfNeeded()
            await context.sessionScope.store.loadPersistedSessions()
            logger.info("Opened project window: \(url.path)")
        } catch {
            logger.error("Failed to open project at \(url.path): \(error)")
            let alert = NSAlert()
            alert.messageText = String(localized: "Failed to open project")
            alert.informativeText = String(localized: "Could not open \"\(url.lastPathComponent)\": \(error.localizedDescription)")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
        }
    }

    func closeProject(at url: URL) {
        if let token = chunkHandlerTokens.removeValue(forKey: url) {
            projectWindows[url]?.projectContext.commandRouter.removeChunkHandler(token: token)
        }
        guard let controller = projectWindows.removeValue(forKey: url) else { return }
        let context = controller.projectContext
        if activeContext?.projectURL == url {
            activeContext = projectWindows.values.first?.projectContext
        }
        persistOpenProjects()
        controller.close()
        // Flush pending debounced writes (session rename, notes autosave, etc.)
        // before tearing down resources. The window is already closed; this Task
        // keeps the context alive until DB writes land.
        Task { @MainActor [context] in
            await context.flushPendingWrites()
            context.close()
            logger.info("Closed project: \(url.path)")
        }
    }

    func showProjectPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Open Project")
        panel.message = String(localized: "Choose a project directory to open in Termura")

        NSApp.activate(ignoringOtherApps: true)

        if let keyWindow = NSApp.keyWindow {
            // Attach as a sheet so the panel is always visible above the current window.
            panel.beginSheetModal(for: keyWindow) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.openProject(at: url)
            }
        } else {
            // No key window (e.g. first launch, all windows closed).
            // runModal() enters a nested AppKit event loop — safe on @MainActor.
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                openProject(at: url)
            }
        }
    }

    /// Restore the most recently opened project or show the picker.
    /// Called on launch and on Dock icon click.
    func restoreLastProjectOrShowPicker() {
        // Task inherits @MainActor from the surrounding @MainActor context — no explicit annotation needed.
        Task { [weak self] in
            await ProjectMigrationService.migrateIfNeeded()
            // openOnLaunchURL (UI tests / URL-scheme deep links): open without persisting to recents.
            if let override = self?.deps?.openOnLaunchURL {
                await self?.performOpenProjectAsync(url: override, persist: false)
                return
            }
            if let lastURL = self?.deps?.appServices.recentProjects.lastOpened() {
                self?.openProject(at: lastURL)
            } else {
                self?.showProjectPicker()
            }
        }
    }

    func tearDown() {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for (url, token) in chunkHandlerTokens {
            projectWindows[url]?.projectContext.commandRouter.removeChunkHandler(token: token)
        }
        chunkHandlerTokens.removeAll()
        // Termination path: flushPendingWrites() already called by handleTermination()
        // before tearDown() is reached. Only resource cleanup needed here.
        for (_, controller) in projectWindows {
            controller.projectContext.close()
        }
    }

    // MARK: - Private

    private func observeWindowFocus() {
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main  // AppKit delivers on main; .main makes it explicit and avoids a Task hop.
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            // Already on the main queue — assumeIsolated avoids a redundant Task allocation.
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                for (_, controller) in projectWindows where controller.window === window {
                    activeContext = controller.projectContext
                    return
                }
            }
        }
    }

    private func persistOpenProjects() {
        let paths = projectWindows.keys.map(\.path)
        deps?.userDefaults.set(paths, forKey: AppConfig.UserDefaultsKeys.openProjectPaths)
    }

    private func setupChunkHandler(for context: ProjectContext) -> UUID {
        let menuBar = deps?.appServices.menuBarService
        let notification = deps?.appServices.notificationService
        return context.commandRouter.onChunkCompleted { chunk in
            if let code = chunk.exitCode, code != 0 {
                menuBar?.recordFailure()
            }
            // Lifecycle: best-effort notification — does not affect core functionality.
            Task { await notification?.notifyIfLong(chunk) }
        }
    }

}
