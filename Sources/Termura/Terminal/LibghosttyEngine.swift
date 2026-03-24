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

    // MARK: - Internal continuations

    private let outputContinuation: AsyncStream<TerminalOutputEvent>.Continuation
    private let shellContinuation: AsyncStream<ShellIntegrationEvent>.Continuation

    // MARK: - Init

    init(sessionID: SessionID) {
        var outCap: AsyncStream<TerminalOutputEvent>.Continuation?
        let outStream = AsyncStream<TerminalOutputEvent> { outCap = $0 }
        guard let outCap else {
            preconditionFailure("AsyncStream continuation must be set synchronously")
        }
        outputStream = outStream
        outputContinuation = outCap

        var shellCap: AsyncStream<ShellIntegrationEvent>.Continuation?
        let shellStream = AsyncStream<ShellIntegrationEvent> { shellCap = $0 }
        guard let shellCap else {
            preconditionFailure("AsyncStream shell continuation must be set synchronously")
        }
        shellEventsStream = shellStream
        shellContinuation = shellCap

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
