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
            fatalError("Cannot initialize database: \(error)")
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
        Task { @MainActor [weak self] in
            await self?.sessionStore.loadPersistedSessions()
        }
        logger.info("Termura launched")
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
                    self.menuBarService.recordFailure()
                }
                let service = self.notificationService
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

// MARK: - KeyboardShortcuts extension

extension KeyboardShortcuts.Name {
    static let toggleVisor = Self("toggleVisor")
}
