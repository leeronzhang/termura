import Foundation
import XCTest
@testable import Termura

@MainActor
final class TerminalCaptureServiceTests: XCTestCase {
    private var repository: MockNoteRepository!
    private var viewModel: NotesViewModel!
    private var service: TerminalCaptureService!

    override func setUp() async throws {
        repository = MockNoteRepository()
        viewModel = NotesViewModel(repository: repository)
        service = TerminalCaptureService(noteRepository: repository, notesViewModel: viewModel)
    }

    // MARK: - Helpers

    private func makeChunk(
        command: String = "ls -la",
        output: [String] = ["total 42", "drwxr-xr-x 5 user staff"],
        exitCode: Int? = 0
    ) -> OutputChunk {
        OutputChunk(
            sessionID: SessionID(),
            commandText: command,
            outputLines: output,
            rawANSI: output.joined(separator: "\n"),
            exitCode: exitCode,
            startedAt: Date(),
            finishedAt: Date()
        )
    }

    // MARK: - Capture

    func testCaptureAppendsToSelectedNote() {
        viewModel.createNote()
        let chunk = makeChunk()
        service.capture(chunk)
        XCTAssertTrue(viewModel.editingBody.contains("ls -la"))
        XCTAssertTrue(viewModel.editingBody.contains("```"))
    }

    func testCaptureCreatesNewNoteIfNoneSelected() {
        XCTAssertNil(viewModel.selectedNoteID)
        let chunk = makeChunk()
        service.capture(chunk)
        XCTAssertNotNil(viewModel.selectedNoteID)
        XCTAssertTrue(viewModel.editingBody.contains("```"))
    }

    func testCaptureFormatContainsCommandHeader() {
        viewModel.createNote()
        service.capture(makeChunk(command: "git status"))
        XCTAssertTrue(viewModel.editingBody.contains("`git status`"))
    }

    func testCaptureFormatContainsExitCode() {
        viewModel.createNote()
        service.capture(makeChunk(exitCode: 1))
        XCTAssertTrue(viewModel.editingBody.contains("exit: 1"))
    }

    func testCaptureFormatWithNilExitCode() {
        viewModel.createNote()
        service.capture(makeChunk(exitCode: nil))
        // Em-dash U+2014 used for nil exit code.
        XCTAssertTrue(viewModel.editingBody.contains("\u{2014}"))
    }

    func testCaptureOutputIncludesChunkLines() {
        viewModel.createNote()
        service.capture(makeChunk(output: ["line one", "line two"]))
        XCTAssertTrue(viewModel.editingBody.contains("line one"))
        XCTAssertTrue(viewModel.editingBody.contains("line two"))
    }
}
