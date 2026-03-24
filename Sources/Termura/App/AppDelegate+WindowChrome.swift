import AppKit
import KeyboardShortcuts
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "WindowChrome")

// MARK: - Window chrome configuration

extension AppDelegate {
    /// Makes the main window title bar transparent and extends content into the toolbar area,
    /// so non-fullscreen appearance matches fullscreen.
    func configureMainWindow() {
        Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            guard let window = NSApp.windows.first(where: { $0.className.contains("AppKitWindow") })
                    ?? NSApp.windows.first else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(self.themeManager.current.background)

            // Disable the system's own visual effect in the toolbar area.
            // .unifiedCompact places an NSVisualEffectView to the right of the
            // traffic lights which creates a lighter strip that clashes with our
            // content material background.
            disableTitlebarEffect(in: window)
            adjustTrafficLights(in: window)

            // Add invisible view to the window's themeFrame (contentView's superview)
            // instead of contentView itself, because contentView is an NSHostingView
            // and adding subviews to it breaks the SwiftUI view hierarchy.
            if let themeFrame = window.contentView?.superview {
                let adjuster = TrafficLightAdjuster(window: window)
                adjuster.frame = .zero
                themeFrame.addSubview(adjuster)
            }

            // Hide traffic-light container BEFORE the exit animation starts,
            // so the user never sees them at the macOS-default position.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.trafficLightContainer(in: window)?.alphaValue = 0
                }
            }

            // After the exit animation finishes, reposition and fade in.
            NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    Task { @MainActor [weak self, weak window] in
                        guard let self, let window else { return }
                        do {
                            try await Task.sleep(nanoseconds: AppConfig.UI.fullScreenExitDelayNanoseconds)
                        } catch { return }
                        self.disableTitlebarEffect(in: window)
                        self.adjustTrafficLights(in: window)
                        await NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = 0.2
                            self.trafficLightContainer(in: window)?.animator().alphaValue = 1
                        }
                    }
                }
            }
        }
    }

    /// Finds and deactivates every NSVisualEffectView inside the titlebar
    /// container so the system toolbar background doesn't paint over our content.
    func disableTitlebarEffect(in window: NSWindow) {
        guard let themebarParent = window.contentView?.superview else { return }
        for container in themebarParent.subviews {
            let name = String(describing: type(of: container))
            guard name.contains("NSTitlebarContainerView") else { continue }
            deactivateEffectViews(in: container)
        }
    }

    func deactivateEffectViews(in view: NSView) {
        if let effectView = view as? NSVisualEffectView {
            effectView.state = .inactive
        }
        for child in view.subviews {
            deactivateEffectViews(in: child)
        }
    }

    func trafficLightContainer(in window: NSWindow) -> NSView? {
        window.standardWindowButton(.closeButton)?.superview
    }

    func adjustTrafficLights(in window: NSWindow) {
        guard let container = trafficLightContainer(in: window),
              let parent = container.superview else { return }
        var frame = container.frame
        frame.origin.x = 12
        frame.origin.y = parent.frame.height - frame.height - 8
        container.frame = frame
    }
}

// MARK: - Traffic-light position keeper

/// Zero-size view added to the window's themeFrame. Its `layout()` is called
/// on every window layout pass (including live resize), so we can synchronously
/// reposition the traffic-light buttons before the frame is rendered.
final class TrafficLightAdjuster: NSView {
    private weak var targetWindow: NSWindow?

    init(window: NSWindow) {
        self.targetWindow = window
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard let window = targetWindow,
              let closeBtn = window.standardWindowButton(.closeButton),
              let container = closeBtn.superview,
              let parent = container.superview else { return }
        var frame = container.frame
        frame.origin.x = 12
        frame.origin.y = parent.frame.height - frame.height - 8
        container.frame = frame
    }
}

// MARK: - KeyboardShortcuts extension

extension KeyboardShortcuts.Name {
    static let toggleVisor = Self("toggleVisor")
}
