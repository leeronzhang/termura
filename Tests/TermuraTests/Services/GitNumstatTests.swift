import Foundation
@testable import Termura
import XCTest

final class GitNumstatTests: XCTestCase {
    func testParsesAddedAndRemoved() {
        let output = """
        12\t3\tSources/Foo.swift
        5\t0\tSources/Bar.swift
        """
        let stats = GitService.parseNumstat(output)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats[0].path, "Sources/Foo.swift")
        XCTAssertEqual(stats[0].added, 12)
        XCTAssertEqual(stats[0].removed, 3)
        XCTAssertEqual(stats[1].added, 5)
        XCTAssertEqual(stats[1].removed, 0)
        XCTAssertFalse(stats[0].isBinary)
    }

    func testParsesBinaryAsDashAndMarksIsBinary() {
        let output = "-\t-\tassets/icon.png"
        let stats = GitService.parseNumstat(output)
        XCTAssertEqual(stats.count, 1)
        XCTAssertNil(stats[0].added)
        XCTAssertNil(stats[0].removed)
        XCTAssertTrue(stats[0].isBinary)
    }

    func testKeepsRenamedPathAsRawString() {
        let output = "5\t2\told/path.swift => new/path.swift"
        let stats = GitService.parseNumstat(output)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats[0].path, "old/path.swift => new/path.swift")
    }

    func testEmptyOutputReturnsEmptyArray() {
        XCTAssertTrue(GitService.parseNumstat("").isEmpty)
    }

    func testSkipsMalformedLines() {
        // Missing path field — should be dropped.
        let output = "12\t3\n5\t0\tValid.swift"
        let stats = GitService.parseNumstat(output)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats[0].path, "Valid.swift")
    }
}
