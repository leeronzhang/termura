import AppKit

extension AppDelegate {
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
