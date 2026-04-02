import AppKit
import GhosttyKit

// MARK: - Keyboard & Event Handling

extension GhosttyTerminalView {
    /// Let Cmd-key shortcuts propagate to the menu/responder chain for app-level actions
    /// (Cmd+D split, Cmd+N new session, Cmd+W close, etc.) instead of sending to ghostty.
    ///
    /// Cmd+V (paste) is handled directly here to avoid the event falling through to
    /// keyDown → ghostty keybinding → clipboard callback, which can crash due to
    /// the callback state pointer being freed before async completion.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers == "v" {
            paste(nil)
            return true
        }
        if event.modifierFlags.contains(.command) {
            return super.performKeyEquivalent(with: event)
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        guard surface != nil else {
            interpretKeyEvents([event])
            return
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        let markedTextBefore = markedText.length > 0

        // Accumulate text produced by interpretKeyEvents (IME composition / dead keys).
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([event])

        // Sync preedit (marked text) state to libghostty.
        syncPreedit(clearIfNeeded: markedTextBefore)

        if let list = keyTextAccumulator, !list.isEmpty {
            // Composed text from IME — send each segment without composing flag.
            for text in list {
                sendKeyEvent(action, event: event, text: text, composing: false)
            }
        } else {
            // Normal key or ongoing composition.
            sendKeyEvent(
                action,
                event: event,
                text: event.ghosttyText,
                composing: markedText.length > 0 || markedTextBefore
            )
        }
    }

    /// Send a key event to the ghostty surface with optional text payload.
    func sendKeyEvent(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        text: String? = nil,
        composing: Bool = false
    ) {
        guard let surface else { return }
        var key = event.makeGhosttyKey(action)
        key.composing = composing
        if let text, !text.isEmpty,
           let codepoint = text.utf8.first, codepoint >= 0x20 {
            text.withCString { ptr in
                key.text = ptr
                _ = ghostty_surface_key(surface, key)
            }
        } else {
            _ = ghostty_surface_key(surface, key)
        }
    }

    /// Sync the preedit (marked text) state to libghostty for inline composition display.
    func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            let len = str.utf8CString.count
            if len > 0 {
                str.withCString { ptr in
                    ghostty_surface_preedit(surface, ptr, UInt(len - 1))
                }
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    // MARK: - Paste

    /// Handle Cmd+V paste by reading text from the system pasteboard and sending
    /// it to the ghostty surface. Without this, the responder chain has no paste
    /// handler when this view is first responder, causing a crash.
    @IBAction func paste(_ sender: Any?) {
        guard let surface else { return }
        guard let str = NSPasteboard.general.string(forType: .string) else { return }
        let len = str.utf8CString.count
        guard len > 1 else { return }
        str.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(len - 1))
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { return }
        let key = event.makeGhosttyKey(GHOSTTY_ACTION_RELEASE)
        _ = ghostty_surface_key(surface, key)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }
        let key = event.makeGhosttyKey(GHOSTTY_ACTION_PRESS)
        _ = ghostty_surface_key(surface, key)
    }

    func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            guard let self, window?.firstResponder === self else { return event }
            keyUp(with: event)
            return nil
        }
    }
}
