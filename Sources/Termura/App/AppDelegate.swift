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

    // MARK: - Fallbacks (used only until first project opens)

    private let fallbackEngineStore: TerminalEngineStore
    private let fallbackSessionStore: SessionStore
    private let fallbackNoteRepo: any NoteRepositoryProtocol
    private let fallbackSearchService: any SearchServiceProtocol

    // MARK: - Project windows

    /// Maps project URL → window controller. Each window owns one project.
    private(set) var projectWindows: [URL: ProjectWindowController] = [:]

    /// The context of the most recently focused project window.
    var activeContext: ProjectContext?

    // MARK: - Convenience accessors (route through activeContext)

    var sessionStore: SessionStore { activeContext?.sessionStore ?? fallbackSessionStore }
    var engineStore: TerminalEngineStore { activeContext?.engineStore ?? fallbackEngineStore }
    var noteRepository: any NoteRepositoryProtocol { activeContext?.noteRepository ?? fallbackNoteRepo }
    var searchService: any SearchServiceProtocol { activeContext?.searchService ?? fallbackSearchService }
    var agentStateStore: AgentStateStore { activeContext?.agentStateStore ?? AgentStateStore() }
    var contextInjectionService: (any ContextInjectionServiceProtocol)? { activeContext?.contextInjectionService }
    var sessionMessageRepository: SessionMessageRepository? { activeContext?.sessionMessageRepository }
    var harnessEventRepository: HarnessEventRepository? { activeContext?.harnessEventRepository }
    var ruleFileRepository: RuleFileRepository? { activeContext?.ruleFileRepository }
    var vectorSearchService: (any VectorSearchServiceProtocol)? { activeContext?.vectorSearchService }
    var sessionHandoffService: (any SessionHandoffServiceProtocol)? { activeContext?.sessionHandoffService }
    var commandRouter: CommandRouter? { activeContext?.commandRouter }

    // MARK: - UI controllers

    var visorController: VisorWindowController?
    @Published var showShellOnboarding = false
    var windowObserver: NSObjectProtocol?

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

        let fbEngineStore = TerminalEngineStore(factory: factory)
        fallbackEngineStore = fbEngineStore
        fallbackSessionStore = SessionStore(engineStore: fbEngineStore)
        fallbackNoteRepo = MockNoteRepository()
        let sessionRepo = MockSessionRepository()
        let noteRepo = MockNoteRepository()
        fallbackSearchService = SearchService(sessionRepository: sessionRepo, noteRepository: noteRepo)

        super.init()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupVisorShortcut()
        checkShellIntegrationOnboarding()
        setupMenuBarActivation()
        observeWindowFocus()
        openLastProjectOrShowPicker()
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
        // Capture per-project handoff info on MainActor before detaching.
        let handoffItems: [TerminationHandoffItem] = projectWindows.values.compactMap { controller -> TerminationHandoffItem? in
            let ctx = controller.projectContext
            guard let activeID = ctx.sessionStore.activeSessionID,
                  let session = ctx.sessionStore.sessions.first(where: { $0.id == activeID }) else {
                return nil
            }
            let chunks = ctx.outputStores[activeID]?.chunks ?? []
            let agentState = ctx.agentStateStore.agents[activeID]
                ?? AgentState(sessionID: activeID, agentType: .unknown)
            return TerminationHandoffItem(
                handoff: ctx.sessionHandoffService,
                session: session,
                chunks: chunks,
                agentState: agentState
            )
        }
        guard !handoffItems.isEmpty else { return .terminateNow }

        Task.detached {
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
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
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
            let context = try ProjectContext.open(
                at: url,
                engineFactory: engineFactory,
                tokenCountingService: tokenCountingService
            )
            let controller = ProjectWindowController(
                projectContext: context,
                themeManager: themeManager,
                fontSettings: fontSettings
            )
            projectWindows[url] = controller
            activeContext = context
            recentProjects.addRecent(url)
            setupChunkHandler(for: context)
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

    // MARK: - Termination Handoff

    /// Captures per-project state needed for session handoff during app termination.
    private struct TerminationHandoffItem {
        let handoff: any SessionHandoffServiceProtocol
        let session: SessionRecord
        let chunks: [OutputChunk]
        let agentState: AgentState
    }
}
