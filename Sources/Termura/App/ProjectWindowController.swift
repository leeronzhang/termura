import AppKit
import SwiftUI

/// NSWindowController that hosts one project window.
/// Each instance owns a `ProjectContext` with its own database, sessions, and services.
@MainActor
final class ProjectWindowController: NSWindowController, NSWindowDelegate {
    let projectContext: ProjectContext
    private let themeManager: ThemeManager
    private let fontSettings: FontSettings
    private let webViewPool: any WebViewPoolProtocol
    private let webRendererBridge: any WebRendererBridgeProtocol
    private let userDefaults: any UserDefaultsStoring

    init(
        projectContext: ProjectContext,
        themeManager: ThemeManager,
        fontSettings: FontSettings,
        webViewPool: any WebViewPoolProtocol,
        webRendererBridge: any WebRendererBridgeProtocol,
        userDefaults: any UserDefaultsStoring = UserDefaults.standard
    ) {
        self.projectContext = projectContext
        self.themeManager = themeManager
        self.fontSettings = fontSettings
        self.webViewPool = webViewPool
        self.webRendererBridge = webRendererBridge
        self.userDefaults = userDefaults

        let window = Self.makeWindow(title: projectContext.displayName)
        super.init(window: window)

        let rootView = ContentView(
            projectContext: projectContext,
            themeManager: themeManager,
            fontSettings: fontSettings,
            webViewPool: webViewPool,
            webRendererBridge: webRendererBridge
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
        guard let frameStr = userDefaults.string(forKey: windowedFrameKey) else { return }
        let frame = NSRectFromString(frameStr)
        guard frame.width > 0, frame.height > 0 else { return }
        // Reject frames that would land entirely off all connected screens.
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return }
        window?.setFrame(frame, display: false)
    }

    private func saveWindowedFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        userDefaults.set(NSStringFromRect(window.frame), forKey: windowedFrameKey)
    }

    /// Restore full-screen state after the window is on screen.
    /// Call from the opener after showWindow + makeKeyAndOrderFront.
    func restoreFullScreenIfNeeded() {
        guard userDefaults.bool(forKey: fullScreenStateKey),
              let window else { return }
        Task { @MainActor [weak window] in
            do {
                try await Task.sleep(for: AppConfig.UI.fullScreenRestoreDelay)
            } catch is CancellationError {
                // CancellationError is expected — window was closed before the delay elapsed.
                return
            }
            window?.toggleFullScreen(nil)
        }
    }

    // MARK: - Hide / restore (shoebox semantics)

    /// True when the user has dismissed the window via the traffic-light close button.
    /// The underlying ProjectContext (PTYs, sessions, DB) stays alive until app termination.
    private(set) var isHiddenByUser: Bool = false

    /// User-initiated hide: window leaves the screen but the controller, context,
    /// and PTY engines remain in memory so sessions survive across reopens.
    func hideForUser() {
        isHiddenByUser = true
        window?.isExcludedFromWindowsMenu = true
        window?.orderOut(nil)
    }

    /// Bring the window back on screen. Idempotent for already-visible windows.
    func restore() {
        isHiddenByUser = false
        window?.isExcludedFromWindowsMenu = false
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Shoebox semantics: traffic-light close (mouse) hides the window so PTY
        // sessions survive while the app keeps running. Cmd+W is intercepted by
        // TabAwareWindow.performClose and routed to tab closure before reaching here.
        // Programmatic teardown (NSApp.terminate, controller.close()) bypasses this
        // delegate entirely, so app-quit still releases everything cleanly.
        hideForUser()
        return false
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowedFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowedFrame()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        userDefaults.set(true, forKey: fullScreenStateKey)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        userDefaults.set(false, forKey: fullScreenStateKey)
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
