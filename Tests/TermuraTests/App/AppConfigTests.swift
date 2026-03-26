import Foundation
import XCTest
@testable import Termura

final class AppConfigTests: XCTestCase {
    // MARK: - Terminal

    func testMaxScrollbackLinesPositive() {
        XCTAssertGreaterThan(AppConfig.Terminal.maxScrollbackLines, 0)
    }

    // MARK: - SLO

    func testSLOLaunchUnderFiveSeconds() {
        XCTAssertLessThan(AppConfig.SLO.launchSeconds, 5.0)
    }

    // MARK: - Context Window

    func testContextWindowWarningBelowCritical() {
        XCTAssertLessThan(
            AppConfig.ContextWindow.warningThreshold,
            AppConfig.ContextWindow.criticalThreshold,
            "Warning threshold must be strictly below critical threshold"
        )
    }

    // MARK: - Font sizes

    func testFontMinBelowDefault() {
        XCTAssertLessThan(AppConfig.Fonts.minSize, AppConfig.Fonts.terminalSize)
    }

    func testFontDefaultBelowMax() {
        XCTAssertLessThan(AppConfig.Fonts.terminalSize, AppConfig.Fonts.maxSize)
    }

    // MARK: - Search

    func testSearchMinQueryLengthPositive() {
        XCTAssertGreaterThan(AppConfig.Search.minQueryLength, 0)
    }

    // MARK: - Session Tree

    func testSessionTreeMaxDepthPositive() {
        XCTAssertGreaterThan(AppConfig.SessionTree.maxDepth, 0)
    }

    // MARK: - Export

    func testExportMaxMessagesPositive() {
        XCTAssertGreaterThan(AppConfig.Export.maxExportMessages, 0)
    }

    // MARK: - AI

    func testTokenEstimateDivisorPositive() {
        XCTAssertGreaterThan(AppConfig.AI.tokenEstimateDivisor, 0)
    }

    // MARK: - Runtime

    func testRuntimeDebounceValuesPositive() {
        XCTAssertGreaterThan(AppConfig.Runtime.searchDebounceSeconds, 0)
        XCTAssertGreaterThan(AppConfig.Runtime.notesAutoSaveSeconds, 0)
        XCTAssertGreaterThan(AppConfig.Runtime.visorAnimationSeconds, 0)
    }

    // MARK: - Git

    func testGitMaxDisplayedFilesPositive() {
        XCTAssertGreaterThan(AppConfig.Git.maxDisplayedFiles, 0)
    }
}
