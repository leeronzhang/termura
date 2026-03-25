import Foundation
import XCTest
@testable import Termura

final class SessionExportServiceTests: XCTestCase {
    private var service: SessionExportService!
    private var exportedURLs: [URL] = []

    override func setUp() async throws {
        service = SessionExportService()
        exportedURLs = []
    }

    override func tearDown() async throws {
        for url in exportedURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    private func makeSession(title: String = "Test Session") -> SessionRecord {
        SessionRecord(title: title)
    }

    private func makeChunk(
        command: String = "echo hello",
        output: [String] = ["hello"],
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

    private func export(
        _ method: (SessionRecord, [OutputChunk]) async throws -> URL,
        session: SessionRecord,
        chunks: [OutputChunk]
    ) async throws -> URL {
        let url = try await method(session, chunks)
        exportedURLs.append(url)
        return url
    }

    // MARK: - HTML export

    func testExportHTMLCreatesFile() async throws {
        let url = try await export(
            service.exportHTML,
            session: makeSession(),
            chunks: [makeChunk()]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testExportHTMLContainsSessionTitle() async throws {
        let url = try await export(
            service.exportHTML,
            session: makeSession(title: "My Session"),
            chunks: [makeChunk()]
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("My Session"))
    }

    func testExportHTMLEscapesAngleBrackets() async throws {
        let url = try await export(
            service.exportHTML,
            session: makeSession(title: "<script>alert(1)</script>"),
            chunks: []
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(content.contains("<script>alert"))
        XCTAssertTrue(content.contains("&lt;script&gt;"))
    }

    // MARK: - JSON export

    func testExportJSONCreatesValidJSON() async throws {
        let url = try await export(
            service.exportJSON,
            session: makeSession(),
            chunks: [makeChunk()]
        )
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["session"])
        XCTAssertNotNil(json?["chunks"])
    }

    func testExportJSONChunkLimitRespected() async throws {
        let limit = AppConfig.Export.maxExportMessages
        let chunks = (0 ..< limit + 10).map { _ in makeChunk() }
        let url = try await export(
            service.exportJSON,
            session: makeSession(),
            chunks: chunks
        )
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let exportedChunks = try XCTUnwrap(json["chunks"] as? [[String: Any]])
        XCTAssertEqual(exportedChunks.count, limit)
    }

    // MARK: - Filename sanitization

    func testExportFileNameRemovesSlashes() async throws {
        let url = try await export(
            service.exportHTML,
            session: makeSession(title: "path/to/file"),
            chunks: []
        )
        let fileName = url.lastPathComponent
        XCTAssertFalse(fileName.contains("/"))
        XCTAssertTrue(fileName.contains("path-to-file"))
    }

    func testExportFileNameRemovesColons() async throws {
        let url = try await export(
            service.exportHTML,
            session: makeSession(title: "12:30:00"),
            chunks: []
        )
        let fileName = url.lastPathComponent
        XCTAssertFalse(fileName.contains(":"))
    }

    func testExportFileNameTruncatesLongNames() async throws {
        let longTitle = String(repeating: "a", count: 200)
        let url = try await export(
            service.exportHTML,
            session: makeSession(title: longTitle),
            chunks: []
        )
        // File name = sanitized title (≤64) + ".html" (5)
        let baseName = url.deletingPathExtension().lastPathComponent
        XCTAssertLessThanOrEqual(baseName.count, 64)
    }

    func testExportFileNameFallbackForEmpty() async throws {
        let url = try await export(
            service.exportHTML,
            session: makeSession(title: ""),
            chunks: []
        )
        let baseName = url.deletingPathExtension().lastPathComponent
        XCTAssertEqual(baseName, "session")
    }

    func testExportFileNameNeutralizedPathTraversal() async throws {
        let url = try await export(
            service.exportHTML,
            session: makeSession(title: "../../../etc/passwd"),
            chunks: []
        )
        let fileName = url.lastPathComponent
        XCTAssertFalse(fileName.contains("/"))
        // The slashes are replaced with dashes, neutralizing the traversal.
        XCTAssertTrue(fileName.contains("-"))
    }
}
