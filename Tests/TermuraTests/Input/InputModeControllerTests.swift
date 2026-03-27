import Foundation
import XCTest
@testable import Termura

@MainActor
final class InputModeControllerTests: XCTestCase {
    private var controller: InputModeController!

    override func setUp() async throws {
        controller = InputModeController()
    }

    func testDefaultModeIsPassthrough() {
        XCTAssertEqual(controller.mode, .passthrough)
    }

    func testSwitchToPassthroughSetsPassthrough() {
        controller.switchToPassthrough()
        XCTAssertEqual(controller.mode, .passthrough)
    }

    func testSwitchToEditorSetsEditor() {
        controller.switchToPassthrough()
        controller.switchToEditor()
        XCTAssertEqual(controller.mode, .editor)
    }
}
