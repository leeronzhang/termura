import WebKit

#if DEBUG

/// Debug preview stub for `WebViewPoolProtocol`.
@MainActor
final class DebugWebViewPool: WebViewPoolProtocol {
    private(set) var vendCallCount = 0
    private(set) var reclaimCallCount = 0
    private(set) var applyThemeCSSCallCount = 0
    private(set) var preheatCallCount = 0
    private(set) var lastAppliedCSS: String?

    func vend() -> WKWebView {
        vendCallCount += 1
        return WKWebView(frame: .zero)
    }

    func reclaim(_ webView: WKWebView) {
        reclaimCallCount += 1
    }

    func applyThemeCSS(_ css: String, to webView: WKWebView) {
        applyThemeCSSCallCount += 1
        lastAppliedCSS = css
    }

    func preheat() {
        preheatCallCount += 1
    }
}

#endif
