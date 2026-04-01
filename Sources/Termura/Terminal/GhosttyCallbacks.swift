import AppKit
import GhosttyKit

// Top-level C callback functions for ghostty_runtime_config_s.
//
// These MUST be defined outside the @MainActor GhosttyAppContext class.
// Swift 6 wraps closures defined inside @MainActor methods with an actor
// isolation thunk — even @convention(c) function pointers. When ghostty's
// renderer/IO threads invoke these callbacks, the thunk triggers
// _swift_task_checkIsolatedSwift → _dispatch_assert_queue_fail.
// File-scope functions are inherently nonisolated, avoiding the crash.

func ghosttyWakeupCb(_ ud: UnsafeMutableRawPointer?) {
    GhosttyAppContext.cWakeup(ud)
}

func ghosttyActionCb(
    _ app: ghostty_app_t?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    guard let app else { return false }
    return GhosttyAppContext.cAction(app, target: target, action: action)
}

func ghosttyReadClipboardCb(
    _ ud: UnsafeMutableRawPointer?,
    _ loc: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) -> Bool {
    GhosttyAppContext.cReadClipboard(ud, loc: loc, state: state)
}

func ghosttyConfirmReadClipboardCb(
    _ ud: UnsafeMutableRawPointer?,
    _ str: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ req: ghostty_clipboard_request_e
) {
    GhosttyAppContext.cConfirmReadClipboard(ud, str: str, state: state, req: req)
}

func ghosttyWriteClipboardCb(
    _ ud: UnsafeMutableRawPointer?,
    _ loc: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ len: Int,
    _ confirm: Bool
) {
    GhosttyAppContext.cWriteClipboard(ud, loc: loc, content: content, len: len, confirm: confirm)
}

func ghosttyCloseSurfaceCb(_ ud: UnsafeMutableRawPointer?, _ alive: Bool) {
    GhosttyAppContext.cCloseSurface(ud, processAlive: alive)
}

// PTY output callback — called from io-reader thread.
// Yields directly to the nonisolated AsyncStream continuation (thread-safe).
func ghosttyPtyOutputCb(_ userdata: UnsafeMutableRawPointer?, _ buf: UnsafePointer<UInt8>?, _ len: Int) {
    guard let userdata, let buf, len > 0 else { return }
    let view = Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()
    let data = Data(bytes: buf, count: len)
    view.ptyOutputContinuation?.yield(.data(data))
    // Scan raw PTY bytes for OSC 133 shell integration sequences (A/B/C).
    // ghostty only fires GHOSTTY_ACTION_COMMAND_FINISHED for D; A/B/C have
    // no corresponding action, so we parse them from the raw stream.
    if let shellCont = view.shellIntegrationContinuation {
        scanOSC133ShellEvents(buf, len: len, continuation: shellCont)
    }
}

// OSC 133 prefix: ESC ] 1 3 3 ;  (6 bytes)
// Terminated by BEL (\x07) or ST (ESC \).
// Only A/B/C are emitted here; D is handled by GHOSTTY_ACTION_COMMAND_FINISHED.
private func scanOSC133ShellEvents(
    _ buf: UnsafePointer<UInt8>,
    len: Int,
    continuation: AsyncStream<ShellIntegrationEvent>.Continuation
) {
    // Minimum sequence length: ESC ] 1 3 3 ; X BEL = 8 bytes
    guard len >= 8 else { return }
    // Fast path: check if ESC exists anywhere in the buffer
    var hasEsc = false
    for i in 0 ..< len where buf[i] == 0x1B {
        hasEsc = true
        break
    }
    guard hasEsc else { return }

    var i = 0
    while i + 7 < len {
        // Look for ESC ]
        guard buf[i] == 0x1B, buf[i + 1] == 0x5D else { i += 1; continue }
        // Check "133;"
        guard buf[i + 2] == 0x31, // '1'
              buf[i + 3] == 0x33, // '3'
              buf[i + 4] == 0x33, // '3'
              buf[i + 5] == 0x3B // ';'
        else { i += 2; continue }
        let cmdByte = buf[i + 6]
        switch cmdByte {
        case 0x41: continuation.yield(.promptStarted)
        case 0x42: continuation.yield(.commandStarted)
        case 0x43: continuation.yield(.executionStarted)
        default: break // 'D' handled by action callback
        }
        i += 7
    }
}
