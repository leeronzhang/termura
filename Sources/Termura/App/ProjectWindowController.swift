import AppKit
import SwiftUI

/// NSWindowController that hosts one project window.
/// Each instance owns a `ProjectContext` with its own database, sessions, and services.
@MainActor
final class ProjectWindowController: NSWindowController, NSWindowDelegate {
    let projectContext: ProjectContext
    private let themeManager: ThemeManager
    private let fontSettings: FontSettings

    init(
        projectContext: ProjectContext,
        themeManager: ThemeManager,
        fontSettings: FontSettings
    ) {
        self.projectContext = projectContext
        self.themeManager = themeManager
        self.fontSettings = fontSettings

        let window = Self.makeWindow(title: projectContext.displayName)
        super.init(window: window)

        let rootView = ContentView(
            projectContext: projectContext,
            themeManager: themeManager,
            fontSettings: fontSettings
        )
        let hostingController = NSHostingController(rootView: rootView)
        // Prevent SwiftUI from resizing the window to fit its content.
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.commandRouter = projectContext.commandRouter
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(projectContext:themeManager:fontSettings:)")
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // When triggered by the traffic light close button (mouse click),
        // allow the window to close normally. When triggered by Cmd+W
        // (keyboard shortcut via performClose), TabAwareWindow routes it
        // to tab closure instead, and this delegate method is never reached.
        return true
    }

    // MARK: - Window factory

    private static func makeWindow(title: String) -> TabAwareWindow {
        let window = TabAwareWindow(
            contentRect: NSRect(x: 0, y: 0, width: AppConfig.UI.projectWindowWidth, height: AppConfig.UI.projectWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: AppConfig.UI.projectWindowMinWidth, height: AppConfig.UI.projectWindowMinHeight)
        // Restore saved frame. setFrameAutosaveName auto-persists on resize/move.
        let autosaveName = "ProjectWindow-\(title)"
        if !window.setFrameUsingName(autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(autosaveName)
        // Ensure window is on a visible screen (guard against external monitor disconnect).
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.center()
        }
        return window
    }
}

// MARK: - Custom NSWindow that intercepts Cmd+W

/// Overrides `performClose` so Cmd+W closes the active content tab
/// instead of closing the entire window. Traffic light close button
/// bypasses this and closes the window normally.
final class TabAwareWindow: NSWindow {
    /// Set by ProjectWindowController after init.
    weak var commandRouter: CommandRouter?

    override func performClose(_ sender: Any?) {
        // Cmd+W triggers performClose with a keyboard event on the current event queue.
        // The traffic light close button triggers performClose with a mouse event.
        // Route only keyboard-initiated closes to tab closure.
        let isKeyboardShortcut = NSApp.currentEvent?.type == .keyDown
        if isKeyboardShortcut, let router = commandRouter {
            router.requestCloseTab()
        } else {
            super.performClose(sender)
        }
    }
}
