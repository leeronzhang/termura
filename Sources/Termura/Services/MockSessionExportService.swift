import Foundation

/// Test double for `SessionExportProtocol`.
actor MockSessionExportService: SessionExportProtocol {
    var stubbedHTMLURL = URL(fileURLWithPath: "/tmp/mock-export.html")
    var stubbedJSONURL = URL(fileURLWithPath: "/tmp/mock-export.json")
    var exportHTMLCallCount = 0
    var exportJSONCallCount = 0

    func exportHTML(
        session: SessionRecord,
        chunks: [OutputChunk]
    ) async throws -> URL {
        exportHTMLCallCount += 1
        return stubbedHTMLURL
    }

    func exportJSON(
        session: SessionRecord,
        chunks: [OutputChunk]
    ) async throws -> URL {
        exportJSONCallCount += 1
        return stubbedJSONURL
    }
}
