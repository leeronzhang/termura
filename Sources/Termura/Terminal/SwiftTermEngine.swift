import AppKit
import Foundation
import OSLog
import SwiftTerm

private let logger = Logger(subsystem: "com.termura.app", category: "SwiftTermEngine")

/// Live terminal engine backed by SwiftTerm's LocalProcessTerminalView.
/// @MainActor: SwiftTerm callbacks fire on main thread.
@MainActor
final class SwiftTermEngine: NSObject, TerminalEngine {
    // MARK: - Public interface

    let outputStream: AsyncStream<TerminalOutputEvent>
    let shellEventsStream: AsyncStream<ShellIntegrationEvent>
    var isRunning = false

    /// The underlying NSView — kept alive as a headless PTY engine; never shown in the view hierarchy.
    let terminalView: TermuraTerminalView

    // MARK: - Internal state (accessible to +PTY extension)

    let continuation: AsyncStream<TerminalOutputEvent>.Continuation
    let shellContinuation: AsyncStream<ShellIntegrationEvent>.Continuation
    let sessionID: SessionID

    // MARK: - Init

    init(
        sessionID: SessionID,
        shell: String,
        currentDirectory: String? = nil,
        columns: UInt16 = AppConfig.Terminal.ptyColumns,
        rows: UInt16 = AppConfig.Terminal.ptyRows
    ) {
        self.sessionID = sessionID

        var outputCap: AsyncStream<TerminalOutputEvent>.Continuation?
        let stream = AsyncStream<TerminalOutputEvent> { outputCap = $0 }
        guard let outputCap else {
            preconditionFailure("AsyncStream continuation must be set synchronously")
        }
        outputStream = stream
        continuation = outputCap

        var shellCap: AsyncStream<ShellIntegrationEvent>.Continuation?
        let shellStream = AsyncStream<ShellIntegrationEvent> { shellCap = $0 }
        guard let shellCap else {
            preconditionFailure("AsyncStream shell continuation must be set synchronously")
        }
        shellEventsStream = shellStream
        shellContinuation = shellCap

        let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        terminalView = TermuraTerminalView(frame: frame)

        super.init()

        // Wire raw PTY data into the output stream.
        // Capture only the Sendable continuation — safe to call from any queue.
        let cap = outputCap
        terminalView.onDataReceived = { slice in
            let data = Data(slice)
            cap.yield(.data(data))
        }

        terminalView.processDelegate = self
        registerOSC133Handler()

        // Defer fork to the next run-loop tick. forkpty() inside a multi-threaded
        // process can corrupt os_unfair_locks if called during init (while SwiftUI
        // is still setting up). Dispatching asynchronously ensures all init-time
        // locks are released before the fork happens.
        Task { @MainActor [weak self] in
            self?.startProcess(shell: shell, currentDirectory: currentDirectory)
        }
    }

    deinit {
        continuation.finish()
        shellContinuation.finish()
    }

    // MARK: - TerminalEngine

    func send(_ text: String) async {
        terminalView.send(txt: text)
    }

    func sendBytes(_ data: Data) async {
        let bytes = [UInt8](data)
        terminalView.send(data: bytes[...])
    }

    func resize(columns: UInt16, rows: UInt16) async {
        terminalView.terminal.resize(cols: Int(columns), rows: Int(rows))
    }

    func cursorLineContent() -> String? {
        let terminal = terminalView.getTerminal()
        let cursorRow = terminal.getCursorLocation().y
        guard let line = terminal.getLine(row: cursorRow) else { return nil }
        return line.translateToString(trimRight: true)
    }

    func linesNearCursor(above count: Int) -> [String] {
        let terminal = terminalView.getTerminal()
        let cursorRow = terminal.getCursorLocation().y
        let clampedCount = min(count, AppConfig.Terminal.maxScrollbackLines)
        let startRow = max(0, cursorRow - clampedCount)
        var lines: [String] = []
        for row in startRow ... cursorRow {
            if let line = terminal.getLine(row: row) {
                lines.append(line.translateToString(trimRight: true))
            }
        }
        return lines
    }

    func terminate() async {
        isRunning = false
        terminalView.terminate()
        shellContinuation.finish()
        continuation.finish()
    }

    // MARK: - OSC 133 Registration

    private func registerOSC133Handler() {
        // Capture only the Sendable continuation — safe to call from any thread.
        let cont = shellContinuation
        terminalView.terminal.registerOscHandler(code: 133) { payload in
            guard let event = OSC133Parser.parse(payload) else { return }
            cont.yield(event)
        }
    }
}
