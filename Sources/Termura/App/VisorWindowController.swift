import AppKit
import SwiftUI

/// Floating panel that slides in from the top of the screen (Visor mode).
/// Uses NSPanel for non-activating, always-on-top behavior.
@MainActor
final class VisorWindowController: NSWindowController {
    private var isVisible = false
    private let projectContext: ProjectContext
    private let themeManager: ThemeManager
    private let fontSettings: FontSettings

    init(projectContext: ProjectContext, themeManager: ThemeManager, fontSettings: FontSettings) {
        self.projectContext = projectContext
        self.themeManager = themeManager
        self.fontSettings = fontSettings

        let panel = VisorWindowController.makePanel()
        super.init(window: panel)

        let rootView = MainView()
            .environmentObject(projectContext)
            .environmentObject(projectContext.commandRouter)
            .environmentObject(projectContext.notesViewModel)
            .environmentObject(themeManager)
            .environmentObject(fontSettings)
        let hostingController = NSHostingController(rootView: rootView)
        panel.contentViewController = hostingController
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(projectContext:themeManager:)")
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
        let panelHeight = screenFrame.height * AppConfig.UI.visorPanelHeightFraction
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
