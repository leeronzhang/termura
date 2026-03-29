import AppKit
import Foundation

/// Test double for TerminalEngine. Captures all interactions for assertion.
@MainActor
final class MockTerminalEngine: TerminalEngine {
    // MARK: - Streams

    let outputStream: AsyncStream<TerminalOutputEvent>
    let shellEventsStream: AsyncStream<ShellIntegrationEvent>

    // MARK: - State

    private(set) var isRunning = true
    let terminalNSView: NSView = .init()
    private(set) var sentTexts: [String] = []
    private(set) var sentBytes: [Data] = []
    private(set) var resizes: [(UInt16, UInt16)] = []
    private(set) var terminateCallCount = 0
    var stubbedLinesNearCursor: [String] = []

    // MARK: - Continuations

    private let continuation: AsyncStream<TerminalOutputEvent>.Continuation
    private let shellContinuation: AsyncStream<ShellIntegrationEvent>.Continuation

    // MARK: - Init

    init() {
        let (outStream, outCont) = AsyncStream.makeStream(
            of: TerminalOutputEvent.self,
            bufferingPolicy: .bufferingNewest(AppConfig.Terminal.streamBufferCapacity)
        )
        outputStream = outStream
        continuation = outCont

        let (shellStream, shellCont) = AsyncStream.makeStream(
            of: ShellIntegrationEvent.self,
            bufferingPolicy: .bufferingNewest(AppConfig.Terminal.streamBufferCapacity)
        )
        shellEventsStream = shellStream
        shellContinuation = shellCont
    }

    // MARK: - Test helpers

    /// Inject a terminal output event for testing.
    func emit(_ event: TerminalOutputEvent) {
        continuation.yield(event)
    }

    /// Inject a shell integration event for testing.
    func emitShellEvent(_ event: ShellIntegrationEvent) {
        shellContinuation.yield(event)
    }

    // MARK: - TerminalEngine

    func send(_ text: String) async {
        sentTexts.append(text)
    }

    func sendBytes(_ data: Data) async {
        sentBytes.append(data)
    }

    func resize(columns: UInt16, rows: UInt16) async {
        resizes.append((columns, rows))
    }

    func cursorLineContent() -> String? { nil }

    func linesNearCursor(above count: Int) -> [String] { stubbedLinesNearCursor }

    func terminate() async {
        isRunning = false
        terminateCallCount += 1
        shellContinuation.finish()
        continuation.finish()
    }
}
