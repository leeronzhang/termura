import Foundation
import XCTest
@testable import Termura

@MainActor
final class FontSettingsTests: XCTestCase {
    private var settings: FontSettings!

    override func setUp() async throws {
        settings = FontSettings()
        // Reset to defaults to avoid UserDefaults pollution across tests.
        settings.resetZoom()
    }

    func testDefaultTerminalFontSize() {
        settings.resetZoom()
        XCTAssertEqual(settings.terminalFontSize, FontSettings.defaultTerminalSize)
    }

    func testZoomInIncrementsTerminalSize() {
        let before = settings.terminalFontSize
        settings.zoomIn()
        XCTAssertEqual(settings.terminalFontSize, before + FontSettings.zoomStep)
    }

    func testZoomInClampsAtMaxSize() {
        settings.terminalFontSize = FontSettings.maxSize
        settings.zoomIn()
        XCTAssertEqual(settings.terminalFontSize, FontSettings.maxSize)
    }

    func testZoomOutDecrementsTerminalSize() {
        let before = settings.terminalFontSize
        settings.zoomOut()
        XCTAssertEqual(settings.terminalFontSize, before - FontSettings.zoomStep)
    }

    func testZoomOutClampsAtMinSize() {
        settings.terminalFontSize = FontSettings.minSize
        settings.zoomOut()
        XCTAssertEqual(settings.terminalFontSize, FontSettings.minSize)
    }

    func testResetZoomRestoresDefaults() {
        settings.zoomIn()
        settings.zoomIn()
        settings.resetZoom()
        XCTAssertEqual(settings.terminalFontSize, FontSettings.defaultTerminalSize)
    }

    func testTerminalNSFontReturnsNonNil() {
        let font = settings.terminalNSFont()
        XCTAssertNotNil(font)
    }

    func testEditorNSFontReturnsNonNil() {
        let font = settings.editorNSFont()
        XCTAssertNotNil(font)
    }
}
