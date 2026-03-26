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

    // MARK: - NSWindowDelegate — intercept Cmd+W to close tabs instead of the window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Route Cmd+W to close the active content tab instead of the window.
        projectContext.commandRouter.requestCloseTab()
        return false
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
        return window
    }
}

// MARK: - Custom NSWindow that intercepts Cmd+W

/// Overrides `performClose` so Cmd+W closes the active content tab
/// instead of closing the entire window. Delegate-based approaches fail
/// because NSHostingController can override the window delegate.
final class TabAwareWindow: NSWindow {
    /// Set by ProjectWindowController after init.
    weak var commandRouter: CommandRouter?

    override func performClose(_ sender: Any?) {
        if let router = commandRouter {
            router.requestCloseTab()
        } else {
            super.performClose(sender)
        }
    }
}
