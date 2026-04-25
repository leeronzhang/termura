import OSLog
import WebKit

private let logger = Logger(subsystem: "com.termura.app", category: "WebViewPool")

/// Production implementation of `WebViewPoolProtocol`.
/// Manages a single shared WKProcessPool and preheats one WKWebView at startup.
@MainActor
final class WebViewPool: WebViewPoolProtocol {
    private var preheatedView: WKWebView?
    private var isPreheated = false

    // MARK: - WebViewPoolProtocol

    func vend() -> WKWebView {
        if let existing = preheatedView {
            preheatedView = nil
            return existing
        }
        return createWebView()
    }

    func reclaim(_ webView: WKWebView) {
        clearContent(webView)
        preheatedView = webView
    }

    func applyThemeCSS(_ css: String, to webView: WKWebView) {
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        let js = "window.termuraRenderer.updateTheme(`\(escaped)`);"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                logger.error("Failed to apply theme CSS: \(error.localizedDescription)")
            }
        }
    }

    func preheat() {
        guard !isPreheated else { return }
        isPreheated = true
        let webView = createWebView()
        preheatedView = webView
        logger.debug("WebViewPool preheated")
    }

    // MARK: - Private

    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        // Enable Safari Web Inspector for debugging in DEBUG builds.
        // Right-click in the rendered note and choose "Inspect Element".
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif
        loadRendererHTML(into: webView)
        return webView
    }

    private func loadRendererHTML(into webView: WKWebView) {
        guard let htmlURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "WebRenderer"
        ) else {
            logger.error("WebRenderer/index.html not found in bundle")
            return
        }
        let directory = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: directory)
    }

    private func clearContent(_ webView: WKWebView) {
        webView.evaluateJavaScript("window.termuraRenderer.clear();") { _, error in
            if let error {
                logger.error("Failed to clear WebView content: \(error.localizedDescription)")
            }
        }
    }
}
