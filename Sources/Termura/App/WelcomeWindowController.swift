import AppKit
import SwiftUI

/// Lightweight `NSWindowController` that hosts the cold-launch Welcome
/// surface. Owns the window's lifecycle (size, centering, close → VM
/// dismiss). Business logic — opening projects, mutating recents,
/// reading defaults — lives in `WelcomeViewModel` and `ProjectLauncher`.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: WelcomeViewModel
    /// Set to `true` once a project-opening action fires, so the
    /// subsequent `windowWillClose` does not re-route through the
    /// "user dismissed without choosing" callback.
    private var didStartFlow = false

    init(viewModel: WelcomeViewModel) {
        self.viewModel = viewModel
        let window = WelcomeWindowController.makeWindow()
        super.init(window: window)
        // NSWindowController defaults to cascading new windows toward
        // the screen's upper-left. We always want our window centered,
        // never cascaded.
        shouldCascadeWindows = false
        window.delegate = self
        // Apply the app-wide brand tint at the hosting boundary — the Welcome
        // window lives outside `TermuraApp`'s SwiftUI Scene, so it doesn't
        // inherit the global `.tint(.brandGreen)` set in TermuraApp.swift.
        // Without this the Toggle's checkbox falls back to system accent blue.
        let host = NSHostingController(rootView: WelcomeView(viewModel: viewModel).tint(.brandGreen))
        window.contentViewController = host
        window.title = String(localized: "Welcome to Termura")
        centerOnActiveScreen()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("Use init(viewModel:)")
    }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Re-center after the window has been ordered front: on first
        // present the screen association becomes definitive, and the
        // SwiftUI hosting view has finished its initial layout. Re-running
        // here is a no-op when nothing moved.
        centerOnActiveScreen()
    }

    /// True geometric center of the active screen's visible frame.
    /// AppKit's built-in `NSWindow.center()` deliberately places the
    /// window above center (~1/3 from the top) — visually unbalanced
    /// for a square-ish welcome card. We use `frameRect(forContentRect:)`
    /// to compute the full frame (titlebar included) from our intended
    /// content size, so the math stays accurate even before SwiftUI's
    /// hosting view has laid out (when `window.frame.size` would lie).
    private func centerOnActiveScreen() {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let contentRect = NSRect(x: 0, y: 0,
                                 width: AppConfig.UI.welcomeWindowWidth,
                                 height: AppConfig.UI.welcomeWindowHeight)
        let frame = window.frameRect(forContentRect: contentRect)
        let origin = NSPoint(x: visible.midX - frame.width / 2,
                             y: visible.midY - frame.height / 2)
        window.setFrame(NSRect(origin: origin, size: frame.size), display: false)
    }

    /// Closes the window without notifying the VM that the user
    /// dismissed it — the caller has already initiated a project open
    /// (recent / new / existing) and the dismiss callback would race
    /// with the project window appearing.
    func dismissAfterFlow() {
        didStartFlow = true
        close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_: Notification) {
        if !didStartFlow {
            viewModel.userDismissed()
        }
    }

    func windowDidBecomeKey(_: Notification) {
        viewModel.refreshRecents()
    }

    // MARK: - Window factory

    private static func makeWindow() -> NSWindow {
        let frame = NSRect(x: 0, y: 0,
                           width: AppConfig.UI.welcomeWindowWidth,
                           height: AppConfig.UI.welcomeWindowHeight)
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        return window
    }
}
