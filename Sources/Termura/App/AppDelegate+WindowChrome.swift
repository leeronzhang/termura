import AppKit
import KeyboardShortcuts
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "WindowChrome")

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

        // WHY: Keep custom titlebar affordances aligned with AppKit fullscreen transitions.
        // OWNER: AppDelegate owns these observer tokens via fullScreenObserverTokens[key].
        // TEARDOWN: scheduleFullScreenObserverCleanup removes every token on window close.
        // TEST: Exercise enter/exit fullscreen and close-window cleanup in window chrome tests.
        // On entering fullscreen: add project label to traffic-light container.
        let enterToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: .main // Sync body — .main + assumeIsolated avoids a Task allocation.
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                guard let window else { return }
                Self.addFullScreenLabel(to: window)
            }
        }

        // WHY: Hide the traffic-light container before the exit animation to avoid a stale overlay.
        // OWNER: AppDelegate owns these observer tokens via fullScreenObserverTokens[key].
        // TEARDOWN: scheduleFullScreenObserverCleanup removes every token on window close.
        // TEST: Exercise enter/exit fullscreen and close-window cleanup in window chrome tests.
        // Hide traffic-light container BEFORE exit animation starts.
        let willExitToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willExitFullScreenNotification,
            object: window,
            queue: .main // Sync body — .main + assumeIsolated avoids a Task allocation.
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                Self.removeFullScreenLabel(from: window)
                self.trafficLightContainer(in: window)?.alphaValue = 0
            }
        }

        // WHY: Recompute traffic-light placement after every resize, including live resize.
        // OWNER: AppDelegate owns these observer tokens via fullScreenObserverTokens[key].
        // TEARDOWN: scheduleFullScreenObserverCleanup removes every token on window close.
        // TEST: Exercise resize handling and fullscreen cleanup in window chrome tests.
        // Reposition traffic lights after every resize (live resize included).
        // didResizeNotification fires synchronously within the resize event, after
        // AppKit has completed its titlebar layout pass — so our repositioning wins.
        let didResizeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main // Sync body — .main + assumeIsolated avoids a Task allocation.
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
        // WHY: Restore titlebar effects only after AppKit finishes the fullscreen exit animation.
        // OWNER: AppDelegate stores this token in fullScreenObserverTokens[key].
        // TEARDOWN: scheduleFullScreenObserverCleanup removes the token when the window closes.
        // TEST: Cover delayed fullscreen exit restoration and early-close cancellation.
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
        // WHY: Remove per-window fullscreen observers when the window lifecycle ends.
        // OWNER: AppDelegate owns the cleanup observer and token registry.
        // TEARDOWN: This observer removes all registered tokens and then releases the registry entry.
        // TEST: Cover window close after fullscreen registration to ensure no observer leaks remain.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main // Sync body — .main + assumeIsolated avoids a Task allocation.
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                if let tokens = fullScreenObserverTokens.removeValue(forKey: key) {
                    for token in tokens {
                        NotificationCenter.default.removeObserver(token)
                    }
                }
            }
        }
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
