import AppKit
import SwiftUI

/// NSWindowController that hosts one project window.
/// Each instance owns a `ProjectContext` with its own database, sessions, and services.
@MainActor
final class ProjectWindowController: NSWindowController {
    let projectContext: ProjectContext
    private let themeManager: ThemeManager
    private let tokenCountingService: TokenCountingService

    init(
        projectContext: ProjectContext,
        themeManager: ThemeManager,
        tokenCountingService: TokenCountingService
    ) {
        self.projectContext = projectContext
        self.themeManager = themeManager
        self.tokenCountingService = tokenCountingService

        let window = Self.makeWindow(title: projectContext.displayName)
        super.init(window: window)

        let rootView = ContentView(
            projectContext: projectContext,
            themeManager: themeManager,
            tokenCountingService: tokenCountingService
        )
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(projectContext:themeManager:tokenCountingService:)")
    }

    // MARK: - Window factory

    private static func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("ProjectWindow-\(title)")
        // Only center if no saved frame was restored by autosave.
        if !window.setFrameUsingName("ProjectWindow-\(title)") {
            window.center()
        }
        return window
    }
}
