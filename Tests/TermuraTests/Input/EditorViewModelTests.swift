import Foundation
import XCTest
@testable import Termura

@MainActor
final class EditorViewModelTests: XCTestCase {
    private var engine: MockTerminalEngine!
    private var modeController: InputModeController!
    private var viewModel: EditorViewModel!

    override func setUp() async throws {
        engine = MockTerminalEngine()
        modeController = InputModeController()
        viewModel = EditorViewModel(engine: engine, modeController: modeController)
    }

    // MARK: - Submit

    func testSubmitClearsText() {
        viewModel.updateText("ls -la")
        viewModel.submit()
        XCTAssertEqual(viewModel.currentText, "")
    }

    func testSubmitSwitchesToPassthrough() {
        viewModel.updateText("pwd")
        viewModel.submit()
        XCTAssertEqual(modeController.mode, .passthrough)
    }

    func testSubmitSendsToEngine() async throws {
        viewModel.updateText("echo hello")
        viewModel.submit()
        // Wait for the Task inside submit to execute.
        try await Task.sleep(for: .milliseconds(50))
        let sent = await engine.sentTexts
        XCTAssertTrue(sent.contains("echo hello\r"))
    }

    func testSubmitPushesToHistory() {
        viewModel.updateText("first")
        viewModel.submit()
        viewModel.updateText("second")
        viewModel.submit()

        // Navigate back should get "second" then "first".
        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.currentText, "second")
        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.currentText, "first")
    }

    // MARK: - History navigation

    func testNavigatePreviousWithEmptyHistoryIsNoop() {
        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.currentText, "")
    }

    func testNavigateNextPastEndReturnsEmpty() {
        viewModel.updateText("cmd")
        viewModel.submit()

        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.currentText, "cmd")

        viewModel.navigateNext()
        XCTAssertEqual(viewModel.currentText, "")
    }

    // MARK: - Update text

    func testUpdateTextSetsCurrentText() {
        viewModel.updateText("new text")
        XCTAssertEqual(viewModel.currentText, "new text")
    }

    func testUpdateTextDuplicateIsNoop() {
        viewModel.updateText("same")
        viewModel.updateText("same")
        // No crash, currentText unchanged.
        XCTAssertEqual(viewModel.currentText, "same")
    }

    // MARK: - Insert newline

    func testInsertNewlineAppendsNewline() {
        viewModel.updateText("line1")
        viewModel.insertNewline()
        XCTAssertEqual(viewModel.currentText, "line1\n")
    }

    // MARK: - Send raw

    func testSendRawSendsToEngine() async throws {
        viewModel.sendRaw("\u{03}") // Ctrl+C
        try await Task.sleep(for: .milliseconds(50))
        let sent = await engine.sentTexts
        XCTAssertTrue(sent.contains("\u{03}"))
    }
}
