import AppKit
import Foundation

/// Operational states for the terminal engine lifecycle.
enum TerminalLifecycleState: String, Sendable {
    /// Resources allocated, surface pending creation.
    case created
    /// Backing surface created and attached to NSView.
    case attached
    /// Child process spawned and IO stream active.
    case running
    /// Terminal terminating; resources being drained and child process kills pending.
    case exiting
    /// Resources fully released; terminal object can be safely deallocated.
    case disposed
}

/// Protocol abstracting the terminal PTY engine.
/// @MainActor: implementations interact with the AppKit render layer.
/// Implementations: LibghosttyEngine (live), DebugTerminalEngine (preview/debug).
@MainActor
protocol TerminalEngine: AnyObject, Sendable {
    /// Current operational state in the lifecycle.
    var state: TerminalLifecycleState { get }

    /// Async stream of output events from the PTY.
    var outputStream: AsyncStream<TerminalOutputEvent> { get }

    /// Async stream of parsed OSC 133 shell integration events.
    var shellEventsStream: AsyncStream<ShellIntegrationEvent> { get }

    /// Send a string to the PTY's stdin (through surface text / paste API).
    func send(_ text: String) async

    /// Send raw bytes to the PTY's stdin.
    func sendBytes(_ data: Data) async

    /// Simulate pressing the Return key.
    /// Bracketed paste (ghostty_surface_text) treats embedded \\r as literal text;
    /// this sends a real key event so the shell executes the pasted command.
    func pressReturn() async

    /// Notify the PTY of a terminal resize.
    func resize(columns: UInt16, rows: UInt16) async

    /// Terminate the PTY process.
    func terminate() async

    /// Whether the underlying PTY process is running.
    var isRunning: Bool { get }

    /// The AppKit view backing this terminal engine, for focus and key routing.
    var terminalNSView: NSView { get }

    /// Text content of the terminal row where the cursor currently sits,
    /// read from the terminal's screen buffer *after* all ANSI sequences have
    /// been applied.  More reliable than scanning raw PTY bytes for TUI apps
    /// (e.g. Claude Code) that position content with cursor-movement escapes
    /// rather than plain newlines.
    func cursorLineContent() -> String?

    /// Returns the text content of lines near the cursor (cursor row and a few
    /// rows above it). TUI apps like Claude Code position the cursor on hint/status
    /// lines below the actual prompt; scanning upward finds the real prompt.
    /// - Parameter count: number of lines above the cursor row to include.
    /// - Returns: array of line strings, ordered top-to-bottom.
    func linesNearCursor(above count: Int) -> [String]

    /// Returns the current scrollback depth: total buffer lines minus visible rows.
    /// Captured at chunk-append time to record where a command's output starts in the buffer.
    func currentScrollLine() -> Int

    /// Scrolls the terminal so the given scrollback position is visible.
    /// `line` is the value previously returned by `currentScrollLine()`.
    /// No-op if the buffer has no scrollback or `line` is out of range.
    func scrollToLine(_ line: Int) async

    /// Whether scroll-position capture/jump is implemented by this engine.
    /// Views use this to avoid recording fake timeline anchors for engines that
    /// do not yet expose scrollback navigation.
    var supportsScrollbackNavigation: Bool { get }

    /// Apply a color theme to the terminal renderer.
    func applyTheme(_ theme: ThemeColors)

    /// Apply a font to the terminal renderer.
    func applyFont(family: String, size: CGFloat)

    /// Snapshot of the currently rendered visible viewport (no scrollback).
    /// Returns `nil` when the engine has no live surface yet (pre-attach
    /// lifecycle or post-terminate). Drives the remote-control screen-frame
    /// push so iOS clients can render REPLs (Claude Code, IRB, Python REPL)
    /// that don't complete chunks via OSC 133;D shell integration.
    func readVisibleScreen() -> TerminalScreenSnapshot?
}

/// Engine-agnostic snapshot returned by `TerminalEngine.readVisibleScreen()`.
/// `lines.count` should equal `rows`; missing trailing rows imply blank lines.
/// Plain text only — colors / attributes / cursor position are intentionally
/// out of scope for the MVP screen-frame push.
struct TerminalScreenSnapshot: Sendable, Equatable {
    let rows: Int
    let cols: Int
    let lines: [String]
}
