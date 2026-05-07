@testable import Termura
import XCTest

final class TerminalOutputEventTests: XCTestCase {
    func testDataEventCarriesBytes() {
        let data = Data([0x1B, 0x5B, 0x41])
        let event = TerminalOutputEvent.data(data)
        guard case let .data(received) = event else {
            XCTFail("Expected .data event")
            return
        }
        XCTAssertEqual(received, data)
    }

    func testProcessExitedCarriesCode() {
        let event = TerminalOutputEvent.processExited(0)
        guard case let .processExited(code) = event else {
            XCTFail("Expected .processExited event")
            return
        }
        XCTAssertEqual(code, 0)
    }

    func testTitleChangedCarriesTitle() {
        let event = TerminalOutputEvent.titleChanged("zsh")
        guard case let .titleChanged(title) = event else {
            XCTFail("Expected .titleChanged event")
            return
        }
        XCTAssertEqual(title, "zsh")
    }

    func testWorkingDirectoryChangedCarriesPath() {
        let path = "/Users/test/project"
        let event = TerminalOutputEvent.workingDirectoryChanged(path)
        guard case let .workingDirectoryChanged(received) = event else {
            XCTFail("Expected .workingDirectoryChanged event")
            return
        }
        XCTAssertEqual(received, path)
    }

    func testAllCasesAreSendable() {
        let events: [TerminalOutputEvent] = [
            .data(Data()),
            .processExited(1),
            .titleChanged("test"),
            .workingDirectoryChanged("/tmp")
        ]
        XCTAssertEqual(events.count, 4)
    }
}
