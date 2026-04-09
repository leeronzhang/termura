import WebKit

/// Manages a shared pool of WKWebView instances for the render panel.
/// Single-instance design: one preheated WebView is vended on demand and reclaimed when done.
@MainActor
protocol WebViewPoolProtocol: AnyObject, Sendable {
    /// Returns a configured WKWebView loaded with the renderer HTML shell.
    /// The caller must call `reclaim(_:)` when the view is no longer displayed.
    func vend() -> WKWebView

    /// Returns a previously vended WKWebView to the pool for reuse.
    /// Clears rendered content but preserves the loaded JS environment.
    func reclaim(_ webView: WKWebView)

    /// Injects updated CSS custom-property declarations into the WebView.
    func applyThemeCSS(_ css: String, to webView: WKWebView)

    /// Pre-creates a WKWebView and loads the renderer shell. Call from a detached task at startup.
    func preheat()
}
