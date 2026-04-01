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
}
