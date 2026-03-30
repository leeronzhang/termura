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
    }

    private var deps: Dependencies?
    private var windowObserver: NSObjectProtocol?
    /// Tracks the chunk-handler token per open project so it can be removed on close.
    private var chunkHandlerTokens: [URL: UUID] = [:]
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

        // If already open, bring existing window to front
        if let existing = projectWindows[url] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        // Open asynchronously so DB migration (inside DatabaseService.init) runs off the main thread.
        // Task inherits @MainActor from the surrounding @MainActor context — no explicit annotation needed.
        Task { [weak self] in
            guard let self, let deps = self.deps else { return }
            // Re-check inside task — a concurrent open for the same URL may have completed.
            if let existing = self.projectWindows[url] {
                existing.window?.makeKeyAndOrderFront(nil)
                return
            }
            do {
                let context = try await ProjectContext.open(
                    at: url,
                    engineFactory: deps.appServices.engineFactory,
                    tokenCountingService: deps.appServices.tokenCountingService,
                    metricsCollector: deps.appServices.metricsCollector
                )
                let controller = ProjectWindowController(
                    projectContext: context,
                    themeManager: deps.appServices.themeManager,
                    fontSettings: deps.appServices.fontSettings
                )
                self.projectWindows[url] = controller
                self.activeContext = context
                controller.onWindowClose = { [weak self] in self?.closeProject(at: url) }
                // Fire the launch-time callback exactly once after the first window opens.
                if self.projectWindows.count == 1 {
                    self.onFirstProjectOpened?(context.commandRouter)
                    self.onFirstProjectOpened = nil
                }
                deps.appServices.recentProjects.addRecent(url)
                self.chunkHandlerTokens[url] = self.setupChunkHandler(for: context)
                self.persistOpenProjects()
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
                alert.messageText = "Failed to open project"
                alert.informativeText = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    func closeProject(at url: URL) {
        if let token = chunkHandlerTokens.removeValue(forKey: url) {
            projectWindows[url]?.projectContext.commandRouter.removeChunkHandler(token: token)
        }
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"
        panel.message = "Choose a project directory to open in Termura"

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
            if let lastURL = self?.deps?.appServices.recentProjects.lastOpened() {
                self?.openProject(at: lastURL)
            } else {
                self?.showProjectPicker()
            }
        }
    }

    // MARK: - Termination

    /// - Parameter metricsFlush: Optional additional async work (e.g. metrics persistence) to include
    ///   in the structured task group so it is protected by the termination timeout.
    ///   `MetricsPersistenceService` is an actor (Sendable) — safe to capture in @Sendable closure.
    func handleTermination(
        metricsFlush: (@Sendable () async -> Void)? = nil
    ) -> NSApplication.TerminateReply {
        let contexts = projectWindows.values.map(\.projectContext)
        let handoffItems: [TerminationHandoffItem] = projectWindows.values.compactMap { controller in
            let ctx = controller.projectContext
            guard let activeID = ctx.sessionScope.store.activeSessionID,
                  let session = ctx.sessionScope.store.session(id: activeID) else {
                return nil
            }
            let chunks = ctx.viewStateManager.outputStores[activeID].map { Array($0.chunks) } ?? []
            let agentState = ctx.sessionScope.agentStates.agents[activeID]
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
        // before actually exiting. We race the flush+handoff work against a hard deadline
        // so a hung DB or network call never prevents the reply from being sent.
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    // Metrics flush runs concurrently with session flush inside the same group,
                    // so both are protected by the shared termination timeout.
                    if let flush = metricsFlush { await flush() }
                    for ctx in contexts { await ctx.flushPendingWrites() }
                    for item in handoffItems {
                        do {
                            try await item.handoff.generateHandoff(
                                session: item.session,
                                chunks: item.chunks,
                                agentState: item.agentState
                            )
                        } catch {
                            logger.error("generateHandoff failed on termination: \(error)")
                        }
                    }
                }
                group.addTask {
                    do {
                        try await Task.sleep(for: .seconds(AppConfig.Runtime.terminationFlushTimeoutSeconds))
                        // Only reached when the deadline fires before work completes.
                        logger.warning("Termination flush deadline exceeded — replying anyway")
                    } catch {
                        // CancellationError thrown when work task finishes first and
                        // TaskGroup cancels this timeout task — this is the normal fast path.
                        logger.debug("Termination deadline cancelled (work completed on time)")
                    }
                }
                // First child to finish (work or timeout) causes the group to return;
                // TaskGroup cancels and awaits the remaining child automatically.
                _ = await group.next()
            }
            Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func tearDown() {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for (url, token) in chunkHandlerTokens {
            projectWindows[url]?.projectContext.commandRouter.removeChunkHandler(token: token)
        }
        chunkHandlerTokens.removeAll()
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
        UserDefaults.standard.set(paths, forKey: AppConfig.UserDefaultsKeys.openProjectPaths)
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

    // MARK: - Termination Handoff Item

    private struct TerminationHandoffItem {
        let handoff: any SessionHandoffServiceProtocol
        let session: SessionRecord
        let chunks: [OutputChunk]
        let agentState: AgentState
    }
}
