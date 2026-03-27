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
        let engineFactory: any TerminalEngineFactory
        let tokenCountingService: any TokenCountingServiceProtocol
        let themeManager: ThemeManager
        let fontSettings: FontSettings
        let notificationService: NotificationService
        let menuBarService: MenuBarService
        let recentProjects: RecentProjectsService
        let windowChromeConfigurator: (NSWindow) -> Void
    }

    private var deps: Dependencies?
    private var windowObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    /// Called once from `applicationDidFinishLaunching` to wire up dependencies and open projects.
    func start(with dependencies: Dependencies) {
        deps = dependencies
        observeWindowFocus()
        restoreLastProjectOrShowPicker()
    }

    // MARK: - Project management

    func openProject(at url: URL) {
        guard let deps else {
            logger.error("ProjectCoordinator not started before openProject call")
            return
        }

        // If already open, bring existing window to front
        if let existing = projectWindows[url] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        do {
            let context = try ProjectContext.open(
                at: url,
                engineFactory: deps.engineFactory,
                tokenCountingService: deps.tokenCountingService
            )
            let controller = ProjectWindowController(
                projectContext: context,
                themeManager: deps.themeManager,
                fontSettings: deps.fontSettings
            )
            projectWindows[url] = controller
            activeContext = context
            deps.recentProjects.addRecent(url)
            setupChunkHandler(for: context)
            persistOpenProjects()
            controller.showWindow(nil)
            if let window = controller.window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                deps.windowChromeConfigurator(window)
            }

            Task { @MainActor in
                await context.sessionStore.loadPersistedSessions()
            }
            logger.info("Opened project window: \(url.path)")
        } catch {
            logger.error("Failed to open project at \(url.path): \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to open project"
            alert.informativeText = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func closeProject(at url: URL) {
        guard let controller = projectWindows.removeValue(forKey: url) else { return }
        controller.projectContext.close()
        controller.close()
        if activeContext?.projectURL == url {
            activeContext = projectWindows.values.first?.projectContext
        }
        persistOpenProjects()
        logger.info("Closed project: \(url.path)")
    }

    func showProjectPicker() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"
        panel.message = "Choose a project directory to open in Termura"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.openProject(at: url)
            }
        }
    }

    /// Restore the most recently opened project or show the picker.
    /// Called on launch and on Dock icon click.
    func restoreLastProjectOrShowPicker() {
        Task { @MainActor [weak self] in
            await ProjectMigrationService.migrateIfNeeded()
            if let lastURL = self?.deps?.recentProjects.lastOpened() {
                self?.openProject(at: lastURL)
            } else {
                self?.showProjectPicker()
            }
        }
    }

    // MARK: - Termination

    func handleTermination() -> NSApplication.TerminateReply {
        let contexts = projectWindows.values.map(\.projectContext)
        let handoffItems: [TerminationHandoffItem] = projectWindows.values.compactMap { controller in
            let ctx = controller.projectContext
            guard let activeID = ctx.sessionStore.activeSessionID,
                  let session = ctx.sessionStore.sessions.first(where: { $0.id == activeID }) else {
                return nil
            }
            let chunks = ctx.viewStateManager.outputStores[activeID].map { Array($0.chunks) } ?? []
            let agentState = ctx.agentStateStore.agents[activeID]
                ?? AgentState(sessionID: activeID, agentType: .unknown)
            return TerminationHandoffItem(
                handoff: ctx.sessionHandoffService,
                session: session,
                chunks: chunks,
                agentState: agentState
            )
        }

        // Even without handoff items, flush pending writes to DB before exiting.
        let needsDefer = !handoffItems.isEmpty || !contexts.isEmpty

        guard needsDefer else { return .terminateNow }

        // Lifecycle: termination — app waits for reply(toApplicationShouldTerminate:)
        // before actually exiting, so these Tasks are guaranteed to complete.
        Task.detached {
            // Flush all pending persistence writes to guarantee DB consistency.
            for ctx in contexts {
                await ctx.flushPendingWrites()
            }

            for item in handoffItems {
                do {
                    try await item.handoff.generateHandoff(
                        session: item.session,
                        chunks: item.chunks,
                        agentState: item.agentState
                    )
                } catch {
                    // Non-critical: app is terminating; handoff is best-effort.
                    logger.error("generateHandoff failed on termination: \(error)")
                }
            }
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func tearDown() {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for (_, controller) in projectWindows {
            controller.projectContext.close()
        }
    }

    // MARK: - Private

    private func observeWindowFocus() {
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
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
        UserDefaults.standard.set(paths, forKey: "openProjectPaths")
    }

    private func setupChunkHandler(for context: ProjectContext) {
        let menuBar = deps?.menuBarService
        let notification = deps?.notificationService
        context.commandRouter.onChunkCompleted { chunk in
            if let code = chunk.exitCode, code != 0 {
                menuBar?.recordFailure()
            }
            // Lifecycle: best-effort notification — does not affect core functionality.
            Task { await notification?.notifyIfLong(chunk) }
        }
    }

    // MARK: - Termination Handoff Item

    private struct TerminationHandoffItem {
        let handoff: any SessionHandoffServiceProtocol
        let session: SessionRecord
        let chunks: [OutputChunk]
        let agentState: AgentState
    }
}
