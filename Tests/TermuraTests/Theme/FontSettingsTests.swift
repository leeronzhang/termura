import Foundation
@testable import Termura
import XCTest

@MainActor
final class FontSettingsTests: XCTestCase {
    private var settings: FontSettings!
    private var isolatedDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.termura.tests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        settings = FontSettings(userDefaults: isolatedDefaults)
    }

    override func tearDown() async throws {
        settings = nil
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        isolatedDefaults = nil
        suiteName = nil
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
