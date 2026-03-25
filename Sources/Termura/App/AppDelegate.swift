import AppKit
import KeyboardShortcuts
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "AppDelegate")

/// Dependency injection root. Owns global services and per-project contexts.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Global services (shared across all projects)

    let engineFactory: any TerminalEngineFactory = LiveTerminalEngineFactory()
    private(set) lazy var themeManager: ThemeManager = .init()
    private(set) lazy var tokenCountingService: TokenCountingService = .init()
    private(set) lazy var notificationService: NotificationService = .init()
    private(set) lazy var menuBarService: MenuBarService = .init()
    private(set) lazy var themeImportService: ThemeImportService = .init()
    let recentProjects = RecentProjectsService()

    // MARK: - Project windows

    /// Maps project URL → window controller. Each window owns one project.
    private(set) var projectWindows: [URL: ProjectWindowController] = [:]

    /// The context of the most recently focused project window.
    private(set) var activeContext: ProjectContext?

    // MARK: - Convenience accessors (route through activeContext)

    var sessionStore: SessionStore { activeContext?.sessionStore ?? fallbackSessionStore }
    var engineStore: TerminalEngineStore { activeContext?.engineStore ?? fallbackEngineStore }
    var noteRepository: any NoteRepositoryProtocol { activeContext?.noteRepository ?? fallbackNoteRepo }
    var searchService: SearchService { activeContext?.searchService ?? fallbackSearchService }
    var agentStateStore: AgentStateStore { activeContext?.agentStateStore ?? AgentStateStore() }
    var contextInjectionService: ContextInjectionService? { activeContext?.contextInjectionService }
    var sessionMessageRepository: SessionMessageRepository? { activeContext?.sessionMessageRepository }
    var harnessEventRepository: HarnessEventRepository? { activeContext?.harnessEventRepository }
    var ruleFileRepository: RuleFileRepository? { activeContext?.ruleFileRepository }
    var vectorSearchService: VectorSearchService? { activeContext?.vectorSearchService }
    var sessionHandoffService: SessionHandoffService? { activeContext?.sessionHandoffService }

    // MARK: - Fallbacks (used only until first project opens)

    private lazy var fallbackEngineStore = TerminalEngineStore(factory: engineFactory)
    private lazy var fallbackSessionStore = SessionStore(engineStore: fallbackEngineStore)
    private lazy var fallbackNoteRepo: any NoteRepositoryProtocol = MockNoteRepository()
    private lazy var fallbackSearchService: SearchService = {
        let sessionRepo = MockSessionRepository()
        let noteRepo = MockNoteRepository()
        return SearchService(sessionRepository: sessionRepo, noteRepository: noteRepo)
    }()

    // MARK: - UI controllers

    private var visorController: VisorWindowController?
    @Published private(set) var showShellOnboarding = false
    private var chunkObserver: NSObjectProtocol?
    private var windowObserver: NSObjectProtocol?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupVisorShortcut()
        checkShellIntegrationOnboarding()
        setupMenuBarActivation()
        setupChunkObserver()
        observeWindowFocus()
        openLastProjectOrShowPicker()
        logger.info("Termura launched")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Capture per-project handoff info on MainActor before detaching.
        let handoffItems: [(SessionHandoffService, SessionRecord)] = projectWindows.values.compactMap { controller in
            let ctx = controller.projectContext
            guard let activeID = ctx.sessionStore.activeSessionID,
                  let session = ctx.sessionStore.sessions.first(where: { $0.id == activeID }) else {
                return nil
            }
            return (ctx.sessionHandoffService, session)
        }
        guard !handoffItems.isEmpty else { return .terminateNow }

        Task.detached {
            for (handoff, session) in handoffItems {
                let state = AgentState(sessionID: session.id, agentType: .unknown)
                do {
                    try await handoff.generateHandoff(
                        session: session,
                        chunks: [],
                        agentState: state
                    )
                } catch {
                    logger.error("generateHandoff failed on termination: \(error)")
                }
            }
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = chunkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for (_, controller) in projectWindows {
            controller.projectContext.close()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Project management

    func openProject(at url: URL) {
        // If already open, bring existing window to front
        if let existing = projectWindows[url] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        do {
            let context = try ProjectContext.open(at: url, engineFactory: engineFactory)
            let controller = ProjectWindowController(
                projectContext: context,
                themeManager: themeManager,
                tokenCountingService: tokenCountingService
            )
            projectWindows[url] = controller
            activeContext = context
            recentProjects.addRecent(url)
            persistOpenProjects()
            controller.showWindow(nil)
            if let window = controller.window {
                configureProjectWindow(window)
            }

            Task { @MainActor in
                await context.sessionStore.loadPersistedSessions()
            }
            logger.info("Opened project window: \(url.path)")
        } catch {
            logger.error("Failed to open project at \(url.path): \(error)")
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

    // MARK: - Visor

    func toggleVisor() {
        guard let context = activeContext else { return }
        if visorController == nil {
            visorController = VisorWindowController(
                sessionStore: context.sessionStore,
                engineStore: context.engineStore,
                themeManager: themeManager,
                tokenCountingService: tokenCountingService,
                searchService: context.searchService,
                noteRepository: context.noteRepository
            )
        }
        visorController?.toggle()
    }

    // MARK: - Shell Integration Onboarding

    private func checkShellIntegrationOnboarding() {
        let installed = UserDefaults.standard.bool(
            forKey: AppConfig.ShellIntegration.installedDefaultsKey
        )
        if !installed {
            showShellOnboarding = true
        }
    }

    // MARK: - Private

    private func persistOpenProjects() {
        let paths = projectWindows.keys.map(\.path)
        UserDefaults.standard.set(paths, forKey: "openProjectPaths")
    }

    private func openLastProjectOrShowPicker() {
        ProjectMigrationService.migrateIfNeeded()
        if let lastURL = recentProjects.lastOpened() {
            openProject(at: lastURL)
        } else {
            showProjectPicker()
        }
    }

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

    private func setupMenuBarActivation() {
        menuBarService.configure { [weak self] in
            self?.bringMainWindowToFront()
        }
    }

    private func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
    }

    private func setupChunkObserver() {
        chunkObserver = NotificationCenter.default.addObserver(
            forName: .chunkCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let chunk = notification.object as? OutputChunk else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let code = chunk.exitCode, code != 0 {
                    menuBarService.recordFailure()
                }
                let service = notificationService
                Task { await service.notifyIfLong(chunk) }
            }
        }
    }

    private func setupVisorShortcut() {
        KeyboardShortcuts.setShortcut(
            .init(.backtick, modifiers: .command),
            for: .toggleVisor
        )
        KeyboardShortcuts.onKeyUp(for: .toggleVisor) { [weak self] in
            self?.toggleVisor()
        }
    }
}
