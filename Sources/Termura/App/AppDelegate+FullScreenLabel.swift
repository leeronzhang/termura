import AppKit

/// Tag used to find/remove the fullscreen project label.
private let fullScreenLabelTag = AppConfig.UI.fullScreenLabelTag

extension AppDelegate {
    // MARK: - Fullscreen project label

    /// Adds a project-name label as a sibling of the traffic-light buttons
    /// inside their shared container, so it appears on titlebar hover.
    static func addFullScreenLabel(to window: NSWindow) {
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

    static func removeFullScreenLabel(from window: NSWindow) {
        guard let closeBtn = window.standardWindowButton(.closeButton),
              let container = closeBtn.superview else { return }
        container.viewWithTag(fullScreenLabelTag)?.removeFromSuperview()
    }
}
