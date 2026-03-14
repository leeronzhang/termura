import AppKit
import SwiftUI

/// Floating panel that slides in from the top of the screen (Visor mode).
/// Uses NSPanel for non-activating, always-on-top behavior.
@MainActor
final class VisorWindowController: NSWindowController {
    private var isVisible = false
    private let sessionStore: SessionStore
    private let engineStore: TerminalEngineStore
    private let themeManager: ThemeManager
    private let tokenCountingService: TokenCountingService
    private let searchService: SearchService
    private let noteRepository: any NoteRepositoryProtocol

    init(
        sessionStore: SessionStore,
        engineStore: TerminalEngineStore,
        themeManager: ThemeManager,
        tokenCountingService: TokenCountingService,
        searchService: SearchService,
        noteRepository: any NoteRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.engineStore = engineStore
        self.themeManager = themeManager
        self.tokenCountingService = tokenCountingService
        self.searchService = searchService
        self.noteRepository = noteRepository

        let panel = VisorWindowController.makePanel()
        super.init(window: panel)

        let rootView = MainView(
            sessionStore: sessionStore,
            engineStore: engineStore,
            themeManager: themeManager,
            tokenCountingService: tokenCountingService,
            searchService: searchService,
            noteRepository: noteRepository
        )
        let hostingController = NSHostingController(rootView: rootView)
        panel.contentViewController = hostingController
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(sessionStore:engineStore:themeManager:tokenCountingService:searchService:noteRepository:)")
    }

    // MARK: - Show / hide

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let screen = NSScreen.main, let panel = window else { return }
        let screenFrame = screen.frame
        let panelHeight = screenFrame.height * 0.55
        let targetFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - panelHeight,
            width: screenFrame.width,
            height: panelHeight
        )
        panel.setFrame(targetFrame, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppConfig.Runtime.visorAnimationSeconds
            panel.animator().alphaValue = 1.0
        }
        isVisible = true
    }

    func hide() {
        guard let panel = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = AppConfig.Runtime.visorAnimationSeconds
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        })
        isVisible = false
    }

    // MARK: - Panel factory

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.alphaValue = 0.0
        panel.backgroundColor = .clear
        panel.hasShadow = true
        return panel
    }
}
