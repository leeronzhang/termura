import Testing
@testable import Termura

@Suite("HTMLRenderer")
struct HTMLRendererTests {

    // MARK: - Helpers

    private func makeChunk(
        command: String = "ls",
        outputLines: [String] = ["output"],
        exitCode: Int? = 0,
        contentType: OutputContentType = .commandOutput
    ) -> OutputChunk {
        OutputChunk(
            sessionID: SessionID(),
            commandText: command,
            outputLines: outputLines,
            rawANSI: outputLines.joined(separator: "\n"),
            exitCode: exitCode,
            startedAt: Date(),
            finishedAt: Date(),
            contentType: contentType
        )
    }

    private func makeSession(
        title: String = "Test",
        branchType: BranchType = .main
    ) -> SessionRecord {
        SessionRecord(title: title, branchType: branchType)
    }

    // MARK: - XSS escaping

    @Test("escapeHTML replaces ampersand")
    func escapeAmpersand() {
        #expect(HTMLRenderer.escapeHTML("a&b") == "a&amp;b")
    }

    @Test("escapeHTML replaces angle brackets")
    func escapeAngleBrackets() {
        let escaped = HTMLRenderer.escapeHTML("<script>alert(1)</script>")
        #expect(escaped == "&lt;script&gt;alert(1)&lt;/script&gt;")
    }

    @Test("escapeHTML replaces double quotes")
    func escapeDoubleQuotes() {
        #expect(HTMLRenderer.escapeHTML("a\"b") == "a&quot;b")
    }

    @Test("escapeHTML replaces single quotes")
    func escapeSingleQuotes() {
        #expect(HTMLRenderer.escapeHTML("a'b") == "a&#39;b")
    }

    @Test("escapeHTML passes through safe characters")
    func escapeSafeChars() {
        let safe = "Hello World 123"
        #expect(HTMLRenderer.escapeHTML(safe) == safe)
    }

    @Test("escapeHTML handles full XSS payload")
    func escapeFullPayload() {
        let payload = "<img onerror=\"alert('xss')\">"
        let escaped = HTMLRenderer.escapeHTML(payload)
        #expect(!escaped.contains("<"))
        #expect(!escaped.contains(">"))
        #expect(!escaped.contains("\""))
        #expect(!escaped.contains("'"))
    }

    // MARK: - Chunk rendering

    @Test("Chunk with exit code 0 has exit-ok class")
    func chunkExitOK() {
        let session = makeSession()
        let chunk = makeChunk(exitCode: 0)
        let html = HTMLRenderer.render(session: session, chunks: [chunk])
        #expect(html.contains("exit-ok"))
    }

    @Test("Chunk with non-zero exit code has exit-fail class")
    func chunkExitFail() {
        let session = makeSession()
        let chunk = makeChunk(exitCode: 1)
        let html = HTMLRenderer.render(session: session, chunks: [chunk])
        #expect(html.contains("exit-fail"))
    }

    @Test("Chunk with nil exit code has no exit badge in summary")
    func chunkNilExitCode() {
        let session = makeSession()
        let chunk = makeChunk(exitCode: nil)
        let html = HTMLRenderer.render(session: session, chunks: [chunk])
        // The CSS stylesheet contains "exit-ok"/"exit-fail" class definitions,
        // so check specifically that no <span class="exit-..."> appears in chunk markup.
        #expect(!html.contains("exit 0"))
        #expect(!html.contains("exit 1"))
    }

    // MARK: - Full render

    @Test("Render starts with DOCTYPE")
    func renderDoctype() {
        let html = HTMLRenderer.render(session: makeSession(), chunks: [])
        #expect(html.contains("<!DOCTYPE html>"))
    }

    @Test("Non-main branch shows badge")
    func renderBranchBadge() {
        let session = makeSession(branchType: .experiment)
        let html = HTMLRenderer.render(session: session, chunks: [])
        #expect(html.contains("badge"))
        #expect(html.contains("experiment"))
    }

    @Test("Main branch shows no badge in header")
    func renderNoBadgeForMain() {
        let session = makeSession(branchType: .main)
        let html = HTMLRenderer.render(session: session, chunks: [])
        // CSS defines ".badge" class, so check the <h1> header area doesn't
        // contain a <span class="badge"> element (main branch should have none).
        let headerRange = html.range(of: "<h1>")
            .flatMap { start in html.range(of: "</h1>").map { start.lowerBound ..< $0.upperBound } }
        if let range = headerRange {
            let header = String(html[range])
            #expect(!header.contains("<span"))
        }
    }

    @Test("Render limits chunks to maxExportMessages")
    func renderChunkLimit() {
        let session = makeSession()
        let limit = AppConfig.Export.maxExportMessages
        let chunks = (0 ..< limit + 5).map { _ in makeChunk() }
        let html = HTMLRenderer.render(session: session, chunks: chunks)

        // Count <details> tags — each chunk gets one.
        let detailsCount = html.components(separatedBy: "<details").count - 1
        #expect(detailsCount == limit)
    }

    @Test("Render escapes session title in output")
    func renderEscapesTitle() {
        let session = makeSession(title: "<script>alert(1)</script>")
        let html = HTMLRenderer.render(session: session, chunks: [])
        #expect(!html.contains("<script>alert"))
        #expect(html.contains("&lt;script&gt;"))
    }
}
