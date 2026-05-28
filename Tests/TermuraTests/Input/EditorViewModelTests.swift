import Foundation
@testable import Termura
import XCTest

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

    func testSubmitClearsText() async throws {
        viewModel.updateText("ls -la")
        viewModel.submit()
        try await yieldForSubmit()
        XCTAssertEqual(viewModel.currentText, "")
    }

    func testSubmitSwitchesToPassthrough() async throws {
        modeController.switchToEditor()
        viewModel.updateText("pwd")
        viewModel.submit()
        try await yieldForSubmit()
        XCTAssertEqual(modeController.mode, .passthrough)
    }

    func testSubmitSendsToEngine() async throws {
        viewModel.updateText("echo hello")
        viewModel.submit()
        try await yieldForSubmit()
        XCTAssertTrue(engine.sentTexts.contains("echo hello"))
        // Submit follows the text with a raw 0x0D via sendBytes (not pressReturn)
        // so it bypasses bracketed-paste wrapping — see EditorViewModel.submit().
        XCTAssertEqual(engine.sentBytes, [Data([0x0D])])
    }

    func testSubmitPushesToHistory() async throws {
        viewModel.updateText("first")
        viewModel.submit()
        try await yieldForSubmit()
        viewModel.updateText("second")
        viewModel.submit()
        try await yieldForSubmit()

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

    func testNavigateNextPastEndReturnsEmpty() async throws {
        viewModel.updateText("cmd")
        viewModel.submit()
        try await yieldForSubmit()

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

    // MARK: - Send raw

    func testSendRawSendsToEngine() async throws {
        viewModel.sendRaw("\u{03}") // Ctrl+C
        try await yieldForDuration(seconds: 0.05)
        let sent = engine.sentTexts
        XCTAssertTrue(sent.contains("\u{03}"))
    }

    func testSubmitUsesTextViewStringOverStaleCurrentText() async throws {
        viewModel.updateText("")
        viewModel.submit(textOverride: "echo hello")

        try await yieldForSubmit()

        XCTAssertTrue(engine.sentTexts.contains("echo hello"))
        XCTAssertEqual(viewModel.currentText, "")
    }

    func testSubmitWithAttachmentsSendsPathPrefix() async throws {
        let url = URL(fileURLWithPath: "/tmp/termura image.png")
        viewModel.addAttachment(url, kind: .image, isTemporary: false)

        viewModel.submit(textOverride: "describe")
        try await yieldForSubmit()

        let sent = try XCTUnwrap(engine.sentTexts.first)
        XCTAssertTrue(sent.contains(url.path.shellEscaped))
        XCTAssertTrue(sent.contains("describe"))
        XCTAssertTrue(viewModel.attachments.isEmpty)
    }

    func testSubmitWithEmptyTextAndNoAttachmentsIsNoop() async throws {
        viewModel.updateText("")

        viewModel.submit(textOverride: "")
        try await yieldForSubmit()

        XCTAssertTrue(engine.sentTexts.isEmpty)
        XCTAssertTrue(engine.sentBytes.isEmpty)
        XCTAssertEqual(viewModel.currentText, "")
    }

    func testSubmitWithMultilineSendsFullText() async throws {
        viewModel.updateText("line1\nline2")

        viewModel.submit()
        try await yieldForSubmit()

        XCTAssertEqual(engine.sentTexts, ["line1\nline2"])
        XCTAssertEqual(engine.sentBytes, [Data([0x0D])])
    }

    func testSubmitFailurePreservesTextAndAttachments() async throws {
        let url = URL(fileURLWithPath: "/tmp/keep.png")
        engine.sendResult = false
        modeController.switchToEditor()
        viewModel.updateText("keep me")
        viewModel.addAttachment(url, kind: .image, isTemporary: false)

        viewModel.submit()
        try await yieldForSubmit()

        XCTAssertEqual(viewModel.currentText, "keep me")
        XCTAssertEqual(viewModel.attachments.map(\.url), [url])
        // send() failure short-circuits before the Return byte fires.
        XCTAssertTrue(engine.sentBytes.isEmpty)
        XCTAssertEqual(modeController.mode, .editor)
    }

    private func yieldForSubmit() async throws {
        try await yieldForDuration(seconds: 0.05)
    }
}
