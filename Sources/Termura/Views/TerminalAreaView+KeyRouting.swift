import AppKit
import SwiftUI

// MARK: - Key and mouse event routing

extension TerminalAreaView {
    /// Ensures focus always lands on EditorTextView when a key is pressed.
    /// Ctrl+letter and Escape are handled by EditorTextView.keyDown -> PTY directly.
    ///
    /// `NSEvent.addLocalMonitorForEvents` monitors the *current thread's* run loop.
    /// Since we install from the main thread, the callback always fires on main.
    /// `dispatchPrecondition` asserts this at runtime in DEBUG builds.
    func installKeyRouter() {
        installKeyEventMonitor()
        installMouseEventMonitor()
    }

    private func installKeyEventMonitor() {
        let modeCtrl = modeController
        let termEngine = engine
        let router = commandRouter
        let sid = sessionID
        let handle = editorHandle
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            dispatchPrecondition(condition: .onQueue(.main))
            // In dual-pane mode, only the focused pane handles key events.
            if router.isDualPaneActive, router.focusedDualPaneID != sid { return event }
            guard let window = NSApp.keyWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Intercept Cmd+K directly to toggle composer.
            if flags == .command, event.charactersIgnoringModifiers == "k" {
                router.toggleComposer(); return nil
            }
            // Escape closes composer (without clearing text).
            if router.showComposer, event.keyCode == 53 { router.dismissComposer(); return nil }
            // Defense-in-depth: when Composer is open and the user pastes (Cmd+V),
            // ensure EditorTextView has first responder before the event is dispatched.
            // This MUST run before the generic Cmd early-exit below — otherwise Cmd+V
            // exits early and the event lands in whatever view currently holds focus
            // (often the terminal PTY after a submit), silently discarding the image.
            // Reproduces on first auto-resume: focusEditor() delay hasn't finished yet
            // when the user pastes, so the terminal still owns first responder.
            if router.showComposer, flags == .command,
               event.charactersIgnoringModifiers == "v",
               let textView = handle.textView, window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
            // Let other Cmd-key shortcuts pass through to the menu system.
            if flags.contains(.command) { return event }
            if router.showComposer { return event }
            // Dual-pane focus switch: Ctrl+left/right arrow while split mode is active.
            // Intercepted here (before passthrough) so the shell never receives the event.
            // Mirrors the composer invariant: focus shift is blocked when composer is open
            // (handled above by the early return).
            if router.isDualPaneActive, flags == .control {
                if event.keyCode == 123 { router.focusDualPane(.left); return nil }
                if event.keyCode == 124 { router.focusDualPane(.right); return nil }
            }
            // Ctrl+1-9: switch to session by index, even in passthrough mode.
            // Must run before the passthrough block so the event is not forwarded to the PTY.
            if flags == .control,
               let ch = event.charactersIgnoringModifiers,
               ch.count == 1,
               let digit = ch.first?.wholeNumberValue,
               (1...9).contains(digit) {
                router.pendingCommand = .selectSession(index: digit - 1)
                return nil
            }
            // In passthrough mode route keys to the terminal.
            if modeCtrl.mode == .passthrough {
                let termView = termEngine.terminalNSView
                if window.firstResponder !== termView { window.makeFirstResponder(termView) }
                termView.keyDown(with: event)
                return nil
            }
            return event
        }
    }

    // Mouse monitor: dual-pane focus tracking only.
    // Composer backdrop dismissal is handled by AppKitClickableOverlay (TerminalAreaView+Subviews).
    //
    // Invariant: while showComposer == true, focusedDualPaneID must not change.
    // Shifting focus to another pane would (a) visually move the composer to that
    // pane and (b) give the terminal NSView first responder, causing Cmd+V paste
    // to land in the PTY instead of the composer editor.
    private func installMouseEventMonitor() {
        let termEngine = engine
        let router = commandRouter
        let sid = sessionID
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if router.isDualPaneActive {
                let termView = termEngine.terminalNSView
                let loc = termView.convert(event.locationInWindow, from: nil)
                if termView.bounds.contains(loc) {
                    // Don't shift pane focus or give the terminal first responder while
                    // the composer is open in the currently focused pane.
                    if router.showComposer && router.focusedDualPaneID != sid { return event }
                    router.focusedDualPaneID = sid
                    if let window = termView.window, window.firstResponder !== termView {
                        window.makeFirstResponder(termView)
                    }
                }
            }
            return event
        }
    }

    func removeKeyRouter() {
        // Do NOT nil editorViewModel.onSubmit here.
        // onSubmit is wired at session-view level (stable across Composer cycles)
        // and uses [weak router] — no retain cycle, no stale-dismiss risk.
        // Clearing it here causes the composer to stay open if TerminalAreaView
        // briefly disappears and reappears while the composer is in use.
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
            mouseEventMonitor = nil
        }
    }
}
