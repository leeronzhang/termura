import AppKit
import Foundation

#if DEBUG
/// Debug preview engine for TerminalEngine.
@MainActor
final class DebugTerminalEngine: TerminalEngine {
    // MARK: - Streams

    let outputStream: AsyncStream<TerminalOutputEvent>
    let shellEventsStream: AsyncStream<ShellIntegrationEvent>

    // MARK: - State

    private(set) var state: TerminalLifecycleState = .running
    var isRunning: Bool { state == .running }
    let terminalNSView: NSView = .init()
    private(set) var sentTexts: [String] = []
    private(set) var sentBytes: [Data] = []
    private(set) var resizes: [(UInt16, UInt16)] = []
    private(set) var terminateCallCount = 0
    var stubbedLinesNearCursor: [String] = []
    var stubbedScrollLine: Int = 0
    private(set) var scrollToLineCalls: [Int] = []

    // MARK: - Continuations

    private let continuation: AsyncStream<TerminalOutputEvent>.Continuation
    private let shellContinuation: AsyncStream<ShellIntegrationEvent>.Continuation

    // MARK: - Init

    init() {
        // WHY: Preview terminal output must emulate the same async-stream lifecycle as the real engine.
        // OWNER: DebugTerminalEngine owns both continuations for its lifetime.
        // TEARDOWN: deinit/close paths finish the mock streams when tests release the engine.
        // TEST: Cover output/shell event emission and shutdown behavior in tests.
        let (outStream, outCont) = AsyncStream.makeStream(
            of: TerminalOutputEvent.self,
            bufferingPolicy: .bufferingNewest(AppConfig.Terminal.streamBufferCapacity)
        )
        outputStream = outStream
        continuation = outCont

        // WHY: Preview shell events need their own stream with the same lifecycle guarantees.
        // OWNER: DebugTerminalEngine owns shellContinuation for its lifetime.
        // TEARDOWN: deinit/close paths finish the shell stream on engine teardown.
        // TEST: Cover shell event emission and stream completion in tests.
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

    private(set) var pressReturnCallCount = 0

    func pressReturn() async {
        pressReturnCallCount += 1
    }

    func sendBytes(_ data: Data) async {
        sentBytes.append(data)
    }

    func resize(columns: UInt16, rows: UInt16) async {
        resizes.append((columns, rows))
    }

    func cursorLineContent() -> String? { nil }

    func linesNearCursor(above count: Int) -> [String] { stubbedLinesNearCursor }

    func currentScrollLine() -> Int { stubbedScrollLine }

    func scrollToLine(_ line: Int) async { scrollToLineCalls.append(line) }

    var supportsScrollbackNavigation: Bool { true }

    func applyTheme(_ theme: ThemeColors) {}
    func applyFont(family: String, size: CGFloat) {}

    func terminate() async {
        state = .exiting
        terminateCallCount += 1
        shellContinuation.finish()
        continuation.finish()
        state = .disposed
    }
}
#endif
