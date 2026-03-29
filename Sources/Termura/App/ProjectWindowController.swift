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

        // Restore windowed frame AFTER contentViewController is set.
        // setFrameAutosaveName/setFrameUsingName is unreliable here because
        // setting contentViewController can trigger a SwiftUI layout pass that
        // overrides the restored frame and re-saves the wrong size to UserDefaults.
        // By restoring explicitly at the end of init, we guarantee our saved frame wins.
        restoreWindowedFrame()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(projectContext:themeManager:fontSettings:)")
    }

    // MARK: - Window state persistence

    private var windowedFrameKey: String {
        AppConfig.UserDefaultsKeys.windowFrame(projectURL: projectContext.projectURL)
    }

    private var fullScreenStateKey: String {
        AppConfig.UserDefaultsKeys.windowFullScreen(projectURL: projectContext.projectURL)
    }

    private func restoreWindowedFrame() {
        guard let frameStr = UserDefaults.standard.string(forKey: windowedFrameKey) else { return }
        let frame = NSRectFromString(frameStr)
        guard frame.width > 0, frame.height > 0 else { return }
        // Reject frames that would land entirely off all connected screens.
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return }
        window?.setFrame(frame, display: false)
    }

    private func saveWindowedFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: windowedFrameKey)
    }

    /// Restore full-screen state after the window is on screen.
    /// Call from the opener after showWindow + makeKeyAndOrderFront.
    func restoreFullScreenIfNeeded() {
        guard UserDefaults.standard.bool(forKey: fullScreenStateKey),
              let window else { return }
        Task { @MainActor [weak window] in
            do {
                try await Task.sleep(for: AppConfig.UI.fullScreenRestoreDelay)
            } catch is CancellationError {
                return
            }
            window?.toggleFullScreen(nil)
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // When triggered by the traffic light close button (mouse click),
        // allow the window to close normally. When triggered by Cmd+W
        // (keyboard shortcut via performClose), TabAwareWindow routes it
        // to tab closure instead, and this delegate method is never reached.
        return true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowedFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowedFrame()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: fullScreenStateKey)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: fullScreenStateKey)
        saveWindowedFrame()
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
        // Disable macOS system-level window tabbing so Cmd+T is not intercepted
        // by the OS before reaching the app's "New Session" menu shortcut.
        window.tabbingMode = .disallowed
        // Center as default; explicit frame restoration happens in init() after
        // contentViewController is set, so SwiftUI layout cannot override it.
        window.center()
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
