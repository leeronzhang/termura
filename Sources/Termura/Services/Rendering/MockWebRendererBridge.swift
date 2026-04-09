import WebKit

#if DEBUG

/// Debug preview stub for `WebRendererBridgeProtocol`.
@MainActor
final class DebugWebRendererBridge: WebRendererBridgeProtocol {
    private(set) var resetCallCount = 0
    private(set) var appendedChunks: [OutputChunk] = []
    private(set) var renderAllCallCount = 0
    private(set) var renderedMarkdownCalls: [(markdown: String, references: [String])] = []

    func reset(webView: WKWebView) async {
        resetCallCount += 1
    }

    func appendChunk(_ chunk: OutputChunk, to webView: WKWebView) async {
        appendedChunks.append(chunk)
    }

    func renderAll(_ chunks: [OutputChunk], to webView: WKWebView) async {
        renderAllCallCount += 1
        appendedChunks.append(contentsOf: chunks)
    }

    func renderMarkdown(_ markdown: String, references: [String], to webView: WKWebView) async {
        renderedMarkdownCalls.append((markdown: markdown, references: references))
    }
}

#endif
