import AppKit
import Foundation

/// Protocol abstracting the terminal PTY engine.
/// @MainActor: implementations interact with the AppKit render layer.
/// Implementations: LibghosttyEngine (live), MockTerminalEngine (tests).
@MainActor
protocol TerminalEngine: AnyObject, Sendable {
    /// Async stream of output events from the PTY.
    var outputStream: AsyncStream<TerminalOutputEvent> { get }

    /// Async stream of parsed OSC 133 shell integration events.
    var shellEventsStream: AsyncStream<ShellIntegrationEvent> { get }

    /// Send a string to the PTY's stdin.
    func send(_ text: String) async

    /// Send raw bytes to the PTY's stdin.
    func sendBytes(_ data: Data) async

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

    /// Apply a color theme to the terminal renderer.
    func applyTheme(_ theme: ThemeColors)

    /// Apply a font to the terminal renderer.
    func applyFont(family: String, size: CGFloat)
}
