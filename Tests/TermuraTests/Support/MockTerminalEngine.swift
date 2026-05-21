import AppKit
import Foundation
@testable import Termura

@MainActor
final class MockTerminalEngine: TerminalEngine {
    let outputStream: AsyncStream<TerminalOutputEvent>
    let shellEventsStream: AsyncStream<ShellIntegrationEvent>

    private(set) var state: TerminalLifecycleState = .running
    var isRunning: Bool { state == .running }
    let terminalNSView: NSView = .init()
    private(set) var sentTexts: [String] = []
    private(set) var sentBytes: [Data] = []
    var sendBytesResult = true
    private(set) var resizes: [(UInt16, UInt16)] = []
    private(set) var terminateCallCount = 0
    var stubbedLinesNearCursor: [String] = []
    var stubbedScrollLine: Int = 0
    private(set) var scrollToLineCalls: [Int] = []

    private let continuation: AsyncStream<TerminalOutputEvent>.Continuation
    private let shellContinuation: AsyncStream<ShellIntegrationEvent>.Continuation

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

    func emit(_ event: TerminalOutputEvent) {
        continuation.yield(event)
    }

    func emitShellEvent(_ event: ShellIntegrationEvent) {
        shellContinuation.yield(event)
    }

    func send(_ text: String) async -> Bool {
        sentTexts.append(text)
        return true
    }

    private(set) var pressReturnCallCount = 0

    func pressReturn() async {
        pressReturnCallCount += 1
    }

    func sendBytes(_ data: Data) async -> Bool {
        sentBytes.append(data)
        return sendBytesResult
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

    func readVisibleScreen() -> TerminalScreenSnapshot? { nil }

    func terminate() async {
        state = .exiting
        terminateCallCount += 1
        shellContinuation.finish()
        continuation.finish()
        state = .disposed
    }
}
