import WebKit

/// Bridges OutputChunk data to the WKWebView renderer via evaluateJavaScript.
/// All methods run on MainActor because WKWebView requires main-thread access.
@MainActor
protocol WebRendererBridgeProtocol: AnyObject, Sendable {
    /// Clear all rendered content in the WebView.
    func reset(webView: WKWebView) async

    /// Append a single chunk as an incremental DOM insertion.
    func appendChunk(_ chunk: OutputChunk, to webView: WKWebView) async

    /// Clear and re-render all chunks (e.g., after theme change or session switch).
    func renderAll(_ chunks: [OutputChunk], to webView: WKWebView) async

    /// Replace the WebView content with rendered markdown.
    /// Used by NoteRenderedView to display a single markdown document.
    /// References are appended as a numbered References section at the bottom.
    /// Backlinks are shown as a "Backlinks" section listing notes that link to this one.
    func renderMarkdown(_ markdown: String, references: [String], backlinks: [String],
                        to webView: WKWebView) async
}
