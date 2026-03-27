import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "LibghosttyEngine")

/// Stub implementation of `TerminalEngine` for the libghostty backend.
/// All methods are no-ops; streams are created but never yield events.
/// Swap `AppConfig.Backend.activeBackend` to `.libghostty` once the
/// native API is available.
@MainActor
final class LibghosttyEngine: TerminalEngine {
    // MARK: - TerminalEngine conformance

    let outputStream: AsyncStream<TerminalOutputEvent>
    let shellEventsStream: AsyncStream<ShellIntegrationEvent>
    var isRunning = false
    let terminalNSView: NSView = .init()

    // MARK: - Internal continuations

    private let outputContinuation: AsyncStream<TerminalOutputEvent>.Continuation
    private let shellContinuation: AsyncStream<ShellIntegrationEvent>.Continuation

    // MARK: - Init

    init(sessionID: SessionID) {
        let (outStream, outCont) = AsyncStream.makeStream(of: TerminalOutputEvent.self)
        outputStream = outStream
        outputContinuation = outCont

        let (shellStream, shellCont) = AsyncStream.makeStream(of: ShellIntegrationEvent.self)
        shellEventsStream = shellStream
        shellContinuation = shellCont

        logger.debug("LibghosttyEngine stub created for session \(sessionID.rawValue)")
    }

    // MARK: - TerminalEngine methods (stubs)

    func send(_ text: String) async {
        // libghostty API stub
    }

    func sendBytes(_ data: Data) async {
        // libghostty API stub
    }

    func resize(columns: UInt16, rows: UInt16) async {
        // libghostty API stub
    }

    func terminate() async {
        isRunning = false
        outputContinuation.finish()
        shellContinuation.finish()
    }

    func cursorLineContent() -> String? {
        // libghostty API stub
        nil
    }

    func linesNearCursor(above count: Int) -> [String] {
        // libghostty API stub
        []
    }
}
