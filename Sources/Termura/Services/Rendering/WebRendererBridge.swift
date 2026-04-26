import Foundation
import OSLog
import WebKit

private let logger = Logger(subsystem: "com.termura.app", category: "WebRendererBridge")

/// Production implementation of `WebRendererBridgeProtocol`.
/// Serializes OutputChunk data to JSON and injects it into the WKWebView renderer.
@MainActor
final class WebRendererBridge: WebRendererBridgeProtocol {
    // MARK: - WebRendererBridgeProtocol

    func reset(webView: WKWebView) async {
        do {
            try await webView.evaluateJavaScript("window.termuraRenderer.clear();")
        } catch {
            logger.error("Failed to clear WebView content: \(error.localizedDescription)")
        }
    }

    func appendChunk(_ chunk: OutputChunk, to webView: WKWebView) async {
        let jsonString = serializeChunk(chunk)
        let js = "window.termuraRenderer.appendChunk('\(escapeForJS(jsonString))');"
        do {
            try await webView.evaluateJavaScript(js)
        } catch {
            logger.error("Failed to append chunk: \(error.localizedDescription)")
        }
    }

    func renderAll(_ chunks: [OutputChunk], to webView: WKWebView) async {
        await reset(webView: webView)
        for chunk in chunks {
            await appendChunk(chunk, to: webView)
        }
    }

    func renderMarkdown(_ markdown: String, references: [String], backlinks: [String],
                        to webView: WKWebView) async {
        let escapedMarkdown = escapeForJS(markdown)
        let referencesJSON = serializeReferences(references)
        let escapedReferences = escapeForJS(referencesJSON)
        let backlinksJSON = serializeReferences(backlinks)
        let escapedBacklinks = escapeForJS(backlinksJSON)
        let js = "window.termuraRenderer.renderMarkdown('\(escapedMarkdown)', '\(escapedReferences)', '\(escapedBacklinks)');"
        do {
            try await webView.evaluateJavaScript(js)
        } catch {
            logger.error("Failed to render markdown: \(error.localizedDescription)")
        }
    }

    private func serializeReferences(_ references: [String]) -> String {
        do {
            let data = try JSONEncoder().encode(references)
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            logger.error("Failed to serialize references: \(error.localizedDescription)")
            return "[]"
        }
    }

    // MARK: - Serialization

    private func serializeChunk(_ chunk: OutputChunk) -> String {
        let payload = ChunkPayload(
            command: chunk.commandText,
            lines: chunk.outputLines,
            contentType: chunk.contentType.rawValue,
            language: chunk.uiContent.language,
            exitCode: chunk.exitCode
        )
        do {
            let data = try JSONEncoder().encode(payload)
            guard let json = String(data: data, encoding: .utf8) else {
                logger.error("Failed to encode chunk payload to UTF-8 string")
                return "{}"
            }
            return json
        } catch {
            logger.error("Failed to serialize chunk: \(error.localizedDescription)")
            return "{}"
        }
    }

    /// Escape a JSON string for safe embedding in a JS single-quoted string literal.
    private func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Payload

private struct ChunkPayload: Encodable {
    let command: String
    let lines: [String]
    let contentType: String
    let language: String?
    let exitCode: Int?
}
