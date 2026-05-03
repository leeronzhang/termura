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
        let ctx = KeyHandlerContext(
            router: commandRouter, modeCtrl: modeController,
            termEngine: engine, sid: sessionID, handle: editorHandle
        )
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            Self.handleKeyDown(event, context: ctx)
        }
    }

    /// Captured dependencies for the key-down handler. All values are value-type copies
    /// frozen at monitor-installation time (struct value semantics).
    private struct KeyHandlerContext {
        let router: CommandRouter
        let modeCtrl: InputModeController
        let termEngine: any TerminalEngine
        let sid: SessionID
        let handle: EditorViewHandle
    }

    /// Processes a local key-down event; returns `nil` to consume or `event` to pass through.
    private static func handleKeyDown(_ event: NSEvent, context ctx: KeyHandlerContext) -> NSEvent? {
        dispatchPrecondition(condition: .onQueue(.main))
        // Only handle events targeting THIS terminal's window. NSEvent local monitors
        // fire for ALL windows; without this guard, keystrokes in window B get routed
        // to window A's responder chain (cross-window input bleed).
        guard let eventWindow = event.window,
              eventWindow === ctx.termEngine.terminalNSView.window else { return event }
        // In dual-pane mode, only the focused pane handles key events.
        if ctx.router.isDualPaneActive, ctx.router.focusedDualPaneID != ctx.sid { return event }
        let window = eventWindow
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "k" { ctx.router.toggleComposer(); return nil }
        // Escape closes composer (without clearing text).
        if ctx.router.showComposer, event.keyCode == 53 { ctx.router.dismissComposer(); return nil }
        // Cmd+V while composer is open: paste directly into EditorTextView and consume event.
        // Changing firstResponder inside a monitor does not redirect the in-flight event —
        // the event was already targeted at the old responder. We must paste programmatically.
        //
        // DUAL-PANE NOTE: each TerminalAreaView installs its own local monitor and they
        // share the window's run loop, so both panes' monitors fire for the same key
        // event. The dual-pane focus guard above only short-circuits the pane that does
        // NOT hold `focusedDualPaneID`. While the composer is open, the mouse monitor
        // intentionally keeps `focusedDualPaneID` pinned to the composer's pane (see
        // `installMouseEventMonitor` invariant) — but the user can still click into the
        // OTHER pane's terminal NSView, making it the actual `firstResponder`. Without a
        // firstResponder check here, the composer's monitor would steal a Cmd+V the user
        // intends for the other pane's terminal. So only intercept when the in-flight
        // first responder is actually inside this pane (composer textView, this pane's
        // terminal NSView, or no specific responder).
        let cmdOnly = flags.subtracting(.capsLock) == .command
        if ctx.router.showComposer, cmdOnly,
           event.charactersIgnoringModifiers == "v",
           let textView = ctx.handle.textView {
            let myTerminal = ctx.termEngine.terminalNSView
            let firstResponder = window.firstResponder
            let belongsToThisPane = firstResponder == nil
                || (firstResponder as AnyObject) === textView
                || (firstResponder as AnyObject) === myTerminal
            if belongsToThisPane {
                if window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
                textView.paste(nil)
                return nil
            }
            // Otherwise fall through — AppKit's responder chain delivers Cmd+V to the
            // actual first responder (e.g., the other pane's terminal NSView).
        }
        if flags.contains(.command) { return event }
        if ctx.router.showComposer { return event }
        // Shift+Ctrl+left/right switches dual-pane focus (intercepted before passthrough).
        // Arrow keys include .numericPad and .function flags; strip them for comparison.
        if ctx.router.isDualPaneActive,
           flags.subtracting([.numericPad, .function]) == [.control, .shift] {
            if event.keyCode == 123 { ctx.router.focusDualPane(.left); return nil }
            if event.keyCode == 124 { ctx.router.focusDualPane(.right); return nil }
        }
        // Ctrl+1-9: switch to session by index; must run before passthrough check.
        if flags == .control,
           let ch = event.charactersIgnoringModifiers,
           ch.count == 1,
           let digit = ch.first?.wholeNumberValue,
           (1 ... 9).contains(digit) {
            ctx.router.pendingCommand = .selectSession(index: digit - 1)
            return nil
        }
        // In passthrough mode route keys to the terminal.
        if ctx.modeCtrl.mode == .passthrough {
            let termView = ctx.termEngine.terminalNSView
            if window.firstResponder !== termView { window.makeFirstResponder(termView) }
            termView.keyDown(with: event)
            return nil
        }
        return event
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
            // Only handle clicks targeting this terminal's window (same cross-window guard as key monitor).
            guard event.window != nil, event.window === termEngine.terminalNSView.window else { return event }
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
