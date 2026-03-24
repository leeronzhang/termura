import AppKit
import KeyboardShortcuts
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "AppDelegate")

/// Dependency injection root. Owns all top-level singletons.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - DI root — all singletons constructed here

    let engineFactory: any TerminalEngineFactory = LiveTerminalEngineFactory()
    private(set) lazy var engineStore: TerminalEngineStore = .init(factory: engineFactory)
    private(set) lazy var themeManager: ThemeManager = .init()
    private(set) lazy var tokenCountingService: TokenCountingService = .init()

    private(set) lazy var databaseService: DatabaseService = {
        do {
            let pool = try DatabaseService.makePool()
            return try DatabaseService(pool: pool)
        } catch {
            logger.error("DatabaseService init failed: \(error)")
            preconditionFailure("Cannot initialize database: \(error)")
        }
    }()

    private(set) lazy var sessionRepository: SessionRepository = .init(db: databaseService)
    private(set) lazy var noteRepository: NoteRepository = .init(db: databaseService)
    private(set) lazy var searchService: SearchService = .init(
        sessionRepository: sessionRepository,
        noteRepository: noteRepository
    )
    private(set) lazy var sessionSnapshotRepository: SessionSnapshotRepository = .init(
        db: databaseService
    )
    private(set) lazy var sessionArchiveService: SessionArchiveService = .init(
        repository: sessionRepository
    )
    private(set) lazy var sessionStore: SessionStore = .init(
        engineStore: engineStore,
        repository: sessionRepository
    )

    // MARK: - Phase 4 Services

    private(set) lazy var notificationService: NotificationService = .init()
    private(set) lazy var menuBarService: MenuBarService = .init()
    private(set) lazy var themeImportService: ThemeImportService = .init()

    // MARK: - Phase 2 (V3.1) Services

    private(set) lazy var agentStateStore: AgentStateStore = .init()
    private(set) lazy var sessionMessageRepository: SessionMessageRepository = .init(db: databaseService)
    private(set) lazy var harnessEventRepository: HarnessEventRepository = .init(db: databaseService)

    // MARK: - Session Handoff

    private(set) lazy var sessionHandoffService: SessionHandoffService = .init(
        messageRepo: sessionMessageRepository,
        harnessEventRepo: harnessEventRepository,
        summarizer: branchSummarizer
    )

    private(set) lazy var contextInjectionService: ContextInjectionService = .init(
        handoffService: sessionHandoffService
    )

    // MARK: - Phase 3 (V3.1) Services

    private(set) lazy var ruleFileRepository: RuleFileRepository = .init(db: databaseService)
    private(set) lazy var experienceCodifier: ExperienceCodifier = .init(
        harnessEventRepo: harnessEventRepository
    )
    private(set) lazy var branchSummarizer: BranchSummarizer = .init()
    private(set) lazy var embeddingService: EmbeddingService = .init()
    private(set) lazy var vectorSearchService: VectorSearchService = .init(
        embeddingService: embeddingService
    )

    // MARK: - UI controllers

    private var visorController: VisorWindowController?
    @Published private(set) var showShellOnboarding = false
    private var chunkObserver: NSObjectProtocol?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupVisorShortcut()
        checkShellIntegrationOnboarding()
        setupMenuBarActivation()
        setupChunkObserver()
        configureMainWindow()
        Task { @MainActor [weak self] in
            await self?.sessionStore.loadPersistedSessions()
        }
        logger.info("Termura launched")
    }

    /// Makes the main window title bar transparent and extends content into the toolbar area,
    /// so non-fullscreen appearance matches fullscreen.
    private func configureMainWindow() {
        Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            guard let window = NSApp.windows.first(where: { $0.className.contains("AppKitWindow") })
                    ?? NSApp.windows.first else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(self.themeManager.current.background)

            // Disable the system's own visual effect in the toolbar area.
            // .unifiedCompact places an NSVisualEffectView to the right of the
            // traffic lights which creates a lighter strip that clashes with our
            // content material background.
            disableTitlebarEffect(in: window)
            adjustTrafficLights(in: window)

            // Add invisible view to contentView — its layout() fires on every
            // window layout pass, keeping traffic lights pinned.
            if let contentView = window.contentView {
                let adjuster = TrafficLightAdjuster(window: window)
                adjuster.frame = .zero
                contentView.addSubview(adjuster)
            }

            // Hide traffic-light container BEFORE the exit animation starts,
            // so the user never sees them at the macOS-default position.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.trafficLightContainer(in: window)?.alphaValue = 0
                }
            }

            // After the exit animation finishes, reposition and fade in.
            NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.disableTitlebarEffect(in: window)
                        self.adjustTrafficLights(in: window)
                        NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = 0.2
                            self.trafficLightContainer(in: window)?.animator().alphaValue = 1
                        }
                    }
                }
            }
        }
    }

    /// Finds and deactivates every NSVisualEffectView inside the titlebar
    /// container so the system toolbar background doesn't paint over our content.
    private func disableTitlebarEffect(in window: NSWindow) {
        guard let themebarParent = window.contentView?.superview else { return }
        for container in themebarParent.subviews {
            let name = String(describing: type(of: container))
            guard name.contains("NSTitlebarContainerView") else { continue }
            deactivateEffectViews(in: container)
        }
    }

    private func deactivateEffectViews(in view: NSView) {
        if let effectView = view as? NSVisualEffectView {
            effectView.state = .inactive
        }
        for child in view.subviews {
            deactivateEffectViews(in: child)
        }
    }

    private func trafficLightContainer(in window: NSWindow) -> NSView? {
        window.standardWindowButton(.closeButton)?.superview
    }

    private func adjustTrafficLights(in window: NSWindow) {
        guard let container = trafficLightContainer(in: window),
              let parent = container.superview else { return }
        var frame = container.frame
        frame.origin.x = 12
        frame.origin.y = parent.frame.height - frame.height - 8
        container.frame = frame
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let activeID = sessionStore.activeSessionID,
              let session = sessionStore.sessions.first(where: { $0.id == activeID }),
              !session.workingDirectory.isEmpty else {
            return .terminateNow
        }

        let service = sessionHandoffService
        Task.detached {
            let state = AgentState(sessionID: session.id, agentType: .unknown)
            do {
                try await service.generateHandoff(
                    session: session,
                    chunks: [],
                    agentState: state
                )
            } catch {
                logger.error("generateHandoff failed on termination: \(error)")
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
        engineStore.terminateAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Visor

    func toggleVisor() {
        if visorController == nil {
            visorController = VisorWindowController(
                sessionStore: sessionStore,
                engineStore: engineStore,
                themeManager: themeManager,
                tokenCountingService: tokenCountingService,
                searchService: searchService,
                noteRepository: noteRepository
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

// MARK: - Traffic-light position keeper

/// Zero-size view added to the window's contentView. Its `layout()` is called
/// on every window layout pass (including live resize), so we can synchronously
/// reposition the traffic-light buttons before the frame is rendered.
private final class TrafficLightAdjuster: NSView {
    private weak var targetWindow: NSWindow?

    init(window: NSWindow) {
        self.targetWindow = window
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard let window = targetWindow,
              let closeBtn = window.standardWindowButton(.closeButton),
              let container = closeBtn.superview,
              let parent = container.superview else { return }
        var frame = container.frame
        frame.origin.x = 12
        frame.origin.y = parent.frame.height - frame.height - 8
        container.frame = frame
    }
}

// MARK: - KeyboardShortcuts extension

extension KeyboardShortcuts.Name {
    static let toggleVisor = Self("toggleVisor")
}
