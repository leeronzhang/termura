import AppKit
import GhosttyKit

// MARK: - Mouse event forwarding to ghostty surface

extension GhosttyTerminalView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    /// Minimum squared view-space travel before a captured (mouse-reporting)
    /// drag is promoted from a forwarded click to a terminal-level selection.
    static let dragSelectThresholdSquared: CGFloat = 9 // 3pt

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        leftMouseDownPoint = convert(event.locationInWindow, from: nil)
        leftMouseDownMods = event.modifierFlags.ghosttyMods
        if ghostty_surface_mouse_captured(surface) {
            // A TUI is consuming mouse events. Defer the press until mouseUp /
            // mouseDragged reveals whether this is a click (forward to the app)
            // or a drag (promote to a ghostty text selection).
            leftDragState = .pendingCaptured
        } else {
            // No mouse reporting: forward the press immediately so ghostty's
            // own selection / click handling runs as usual.
            leftDragState = .forwarding
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT,
                                             leftMouseDownMods)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        switch leftDragState {
        case .selectingCaptured:
            // Finalize the synthesized selection (triggers copy-on-select).
            let mods = shifted(event.modifierFlags.ghosttyMods)
            ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
        case .pendingCaptured:
            // Never crossed the drag threshold: deliver a real click to the app.
            ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, leftMouseDownMods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, leftMouseDownMods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, leftMouseDownMods)
        case .forwarding, .idle:
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT,
                                             event.modifierFlags.ghosttyMods)
        }
        leftDragState = .idle
    }

    override func rightMouseDown(with event: NSEvent) {
        // Show Termura context menu instead of forwarding to ghostty.
        guard let contextMenu = menu(for: event) else { return }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, event.modifierFlags.ghosttyMods)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        switch leftDragState {
        case .pendingCaptured:
            let dx = pos.x - leftMouseDownPoint.x
            let dy = pos.y - leftMouseDownPoint.y
            guard (dx * dx + dy * dy) >= Self.dragSelectThresholdSquared else { return }
            beginCapturedSelection(currentPoint: pos)
            leftDragState = .selectingCaptured
        case .selectingCaptured:
            ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y,
                                      shifted(event.modifierFlags.ghosttyMods))
        case .forwarding, .idle:
            ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y,
                                      event.modifierFlags.ghosttyMods)
        }
    }

    override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    /// Synthesizes a shift-augmented left press anchored at the original
    /// mouseDown point, then drags to `currentPoint`. The shift modifier makes
    /// ghostty bypass the application's mouse reporting and build its own text
    /// selection (see Surface.zig `mouseButtonCallback` / `cursorPosCallback`).
    private func beginCapturedSelection(currentPoint: NSPoint) {
        guard let surface else { return }
        let anchorY = frame.height - leftMouseDownPoint.y
        // A leftover selection would make ghostty's shift-click "extend
        // selection" path (Surface.zig mouseButtonCallback) stretch the
        // previous selection into this fresh drag. Under mouse reporting the
        // only reset is a non-shift click (which the app also receives, and
        // which clears the selection + resets the click counter together).
        if ghostty_surface_has_selection(surface) {
            ghostty_surface_mouse_pos(surface, leftMouseDownPoint.x, anchorY, leftMouseDownMods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, leftMouseDownMods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, leftMouseDownMods)
        }
        let mods = shifted(leftMouseDownMods)
        ghostty_surface_mouse_pos(surface, leftMouseDownPoint.x, anchorY, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
        ghostty_surface_mouse_pos(surface, currentPoint.x, frame.height - currentPoint.y, mods)
    }

    /// Returns `mods` with the shift bit forced on.
    private func shifted(_ mods: ghostty_input_mods_e) -> ghostty_input_mods_e {
        ghostty_input_mods_e(mods.rawValue | GHOSTTY_MODS_SHIFT.rawValue)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas { x *= 2; y *= 2 }
        // ghostty_input_scroll_mods_t is a packed Int32 bitmask:
        // bit 0 = precision, bits 1-3 = momentum phase
        var mods: Int32 = 0
        if event.hasPreciseScrollingDeltas { mods |= 0b0000_0001 }
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }
}
