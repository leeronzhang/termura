import AppKit
import SwiftUI

// MARK: - FullScreen observer modifier

/// Captures the hosting NSWindow and updates `isFullScreen` in response to enter/exit
/// fullscreen notifications, scoped to this specific window instance.
struct FullScreenObservingModifier: ViewModifier {
    @Binding var isFullScreen: Bool
    @Binding var hostingWindow: NSWindow?
    private var notificationCenter: NotificationCenter? {
        GlobalEnvironmentDefaults.notificationCenter as? NotificationCenter
    }

    func body(content: Content) -> some View {
        let center = notificationCenter ?? .default
        let enterPublisher = center.publisher(for: NSWindow.didEnterFullScreenNotification)
        let exitPublisher = center.publisher(for: NSWindow.didExitFullScreenNotification)
        return content
            // Capture the hosting NSWindow so observers are filtered per-window.
            // Required for correctness when multiple project windows are open.
            .background(HostingWindowCapture { window in
                hostingWindow = window
                isFullScreen = window.styleMask.contains(.fullScreen)
            })
            .onReceive(enterPublisher) { notification in
                guard (notification.object as? NSWindow) === hostingWindow else { return }
                isFullScreen = true
            }
            .onReceive(exitPublisher) { notification in
                guard (notification.object as? NSWindow) === hostingWindow else { return }
                isFullScreen = false
            }
    }
}

// MARK: - Hosting window capture

/// Transparent NSViewRepresentable that resolves the hosting NSWindow via viewDidMoveToWindow.
/// This is the only reliable way to obtain the specific NSWindow for a SwiftUI view in a
/// multi-window app. The result is used to scope NotificationCenter observers to one window.
struct HostingWindowCapture: NSViewRepresentable {
    let onWindowFound: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onWindowFound = onWindowFound
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {}

    final class CaptureView: NSView {
        var onWindowFound: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // viewDidMoveToWindow is called on the main thread. Invoking the callback
            // synchronously (rather than via Task { @MainActor }) ensures hostingWindow
            // is set in the same RunLoop cycle, so fullscreen notifications that fire
            // immediately cannot be silently dropped by the window-identity guard.
            MainActor.assumeIsolated { onWindowFound?(window) }
        }
    }
}
