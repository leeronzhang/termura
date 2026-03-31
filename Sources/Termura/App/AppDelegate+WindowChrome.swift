import AppKit
import KeyboardShortcuts
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "WindowChrome")

/// Tag used to find/remove the fullscreen project label.
private let fullScreenLabelTag = AppConfig.UI.fullScreenLabelTag

// MARK: - Window chrome configuration

extension AppDelegate {
    /// Configures the given project window: transparent titlebar, traffic-light
    /// repositioning, and fullscreen project-name label.
    func configureProjectWindow(_ window: NSWindow) {
        Task { @MainActor in
            do {
                try await Task.sleep(for: AppConfig.UI.windowConfigDelay)
            } catch is CancellationError {
                // CancellationError is expected — window may have closed before the delay fired.
                return
            } catch {
                logger.warning("Window config delay failed: \(error.localizedDescription)")
                return
            }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(self.services.themeManager.current.background)

            disableTitlebarEffect(in: window)
            adjustTrafficLights(in: window)

            if let themeFrame = window.contentView?.superview {
                let adjuster = TrafficLightAdjuster(window: window)
                adjuster.frame = .zero
                themeFrame.addSubview(adjuster)
            }

            observeFullScreenTransitions(window: window)
        }
    }

    /// Legacy entry point — finds the first available window and configures it.
    func configureMainWindow() {
        guard let window = NSApp.windows.first(where: {
            !($0 is NSPanel) && $0.contentViewController != nil
        }) else { return }
        configureProjectWindow(window)
    }

    // MARK: - Fullscreen transitions

    private func observeFullScreenTransitions(window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard fullScreenObserverTokens[key] == nil else { return }

        // On entering fullscreen: add project label to traffic-light container.
        let enterToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: .main  // Sync body — .main + assumeIsolated avoids a Task allocation.
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                guard let window else { return }
                Self.addFullScreenLabel(to: window)
            }
        }

        // Hide traffic-light container BEFORE exit animation starts.
        let willExitToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willExitFullScreenNotification,
            object: window,
            queue: .main  // Sync body — .main + assumeIsolated avoids a Task allocation.
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                Self.removeFullScreenLabel(from: window)
                self.trafficLightContainer(in: window)?.alphaValue = 0
            }
        }

        // Reposition traffic lights after every resize (live resize included).
        // didResizeNotification fires synchronously within the resize event, after
        // AppKit has completed its titlebar layout pass — so our repositioning wins.
        let didResizeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main  // Sync body — .main + assumeIsolated avoids a Task allocation.
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, !window.styleMask.contains(.fullScreen) else { return }
                self.adjustTrafficLights(in: window)
            }
        }

        // After exit animation finishes, reposition traffic lights and fade in.
        let didExitToken = makeDidExitFullScreenObserver(window: window)

        fullScreenObserverTokens[key] = [didResizeToken, enterToken, willExitToken, didExitToken]
        scheduleFullScreenObserverCleanup(window: window, key: key)
    }

    private func makeDidExitFullScreenObserver(window: NSWindow) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: nil
        ) { [weak self, weak window] _ in
            Task { @MainActor [weak self, weak window] in
                guard let self, let window else { return }
                do {
                    try await Task.sleep(for: AppConfig.UI.fullScreenExitDelay)
                } catch is CancellationError {
                    // CancellationError is expected — window closed before exit animation completed.
                    return
                } catch {
                    logger.warning("Full-screen exit delay failed: \(error.localizedDescription)")
                    return
                }
                disableTitlebarEffect(in: window)
                adjustTrafficLights(in: window)
                await NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = AppConfig.UI.trafficLightFadeSeconds
                    self.trafficLightContainer(in: window)?.animator().alphaValue = 1
                }
            }
        }
    }

    /// Registers a one-shot `willCloseNotification` observer that removes the fullscreen
    /// transition tokens from the registry when the window is closed.
    private func scheduleFullScreenObserverCleanup(window: NSWindow, key: ObjectIdentifier) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main  // Sync body — .main + assumeIsolated avoids a Task allocation.
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                if let tokens = self.fullScreenObserverTokens.removeValue(forKey: key) {
                    for token in tokens { NotificationCenter.default.removeObserver(token) }
                }
            }
        }
    }

    // MARK: - Fullscreen project label

    /// Adds a project-name label as a sibling of the traffic-light buttons
    /// inside their shared container, so it appears on titlebar hover.
    private static func addFullScreenLabel(to window: NSWindow) {
        guard let closeBtn = window.standardWindowButton(.closeButton),
              let container = closeBtn.superview else { return }

        // Remove existing label if any (e.g. rapid toggle).
        removeFullScreenLabel(from: window)

        let label = NSTextField(labelWithString: window.title)
        label.tag = fullScreenLabelTag
        label.font = .systemFont(ofSize: AppConfig.UI.fullScreenLabelFontSize, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()

        container.addSubview(label)

        // Position to the right of the rightmost traffic-light button.
        let zoomBtn = window.standardWindowButton(.zoomButton) ?? closeBtn
        let rightEdge = zoomBtn.frame.maxX
        let labelY = zoomBtn.frame.midY - label.frame.height / 2
        label.frame.origin = NSPoint(x: rightEdge + AppConfig.UI.fullScreenLabelSpacing, y: labelY)
    }

    private static func removeFullScreenLabel(from window: NSWindow) {
        guard let closeBtn = window.standardWindowButton(.closeButton),
              let container = closeBtn.superview else { return }
        container.viewWithTag(fullScreenLabelTag)?.removeFromSuperview()
    }

    // MARK: - Titlebar helpers

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
        frame.origin.x = AppConfig.UI.trafficLightX
        frame.origin.y = parent.frame.height - frame.height - AppConfig.UI.trafficLightTopInset
        container.frame = frame
        // Capture the real container height so SwiftUI can center the sidebar toggle
        // at trafficLightCenterY without relying on a guessed constant.
        AppConfig.UI.trafficLightContainerHeight = frame.height
    }
}

// MARK: - Traffic-light position keeper

/// Zero-size view added to the window's themeFrame. Its `layout()` is called
/// on every window layout pass (including live resize), so we can synchronously
/// reposition the traffic-light buttons before the frame is rendered.
@MainActor
final class TrafficLightAdjuster: NSView {
    private weak var targetWindow: NSWindow?

    init(window: NSWindow) {
        targetWindow = window
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { preconditionFailure("Use init(window:)") }

    override func layout() {
        super.layout()
        guard let window = targetWindow,
              let closeBtn = window.standardWindowButton(.closeButton),
              let container = closeBtn.superview,
              let parent = container.superview else { return }
        var frame = container.frame
        frame.origin.x = AppConfig.UI.trafficLightX
        frame.origin.y = parent.frame.height - frame.height - AppConfig.UI.trafficLightTopInset
        container.frame = frame
        AppConfig.UI.trafficLightContainerHeight = frame.height
    }
}

// MARK: - Visor

extension AppDelegate {
    func toggleVisor() {
        guard let context = projectCoordinator.activeContext else { return }
        if visorController == nil {
            visorController = VisorWindowController(
                projectContext: context,
                themeManager: services.themeManager,
                fontSettings: services.fontSettings
            )
        }
        visorController?.toggle()
    }
}

// MARK: - KeyboardShortcuts extension

extension KeyboardShortcuts.Name {
    static let toggleVisor = Self("toggleVisor")
}
