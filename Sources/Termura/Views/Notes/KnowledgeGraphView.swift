import OSLog
import SwiftUI
import WebKit

private let logger = Logger(subsystem: "com.termura.app", category: "KnowledgeGraphView")

/// D3.js force-directed knowledge graph rendered in an independent WKWebView.
/// Does not share the markdown WebViewPool — loads its own `knowledge-graph.html`.
struct KnowledgeGraphView: NSViewRepresentable {
    let theme: ThemeColors
    let graphJSON: String
    /// Called when a note node is clicked (title).
    var onOpenNote: ((String) -> Void)?
    /// Called when a tag node is clicked (tag label).
    var onFilterTag: ((String) -> Void)?

    func makeNSView(context: Context) -> KnowledgeGraphContainerNSView {
        let webView = Self.createWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.pendingGraphJSON = graphJSON
        context.coordinator.webView = webView
        context.coordinator.onOpenNote = onOpenNote
        context.coordinator.onFilterTag = onFilterTag

        let container = KnowledgeGraphContainerNSView(webView: webView)
        container.lastTheme = theme
        container.lastGraphJSON = ""

        let css = ThemeCSSGenerator.generate(from: theme)
        applyThemeCSS(css, to: webView)
        loadGraphHTML(into: webView)
        return container
    }

    func updateNSView(_ container: KnowledgeGraphContainerNSView, context: Context) {
        context.coordinator.onOpenNote = onOpenNote
        context.coordinator.onFilterTag = onFilterTag

        if container.lastTheme != theme {
            container.lastTheme = theme
            let css = ThemeCSSGenerator.generate(from: theme)
            applyThemeCSS(css, to: container.webView)
        }
        if container.lastGraphJSON != graphJSON {
            container.lastGraphJSON = graphJSON
            renderGraph(graphJSON, to: container.webView)
        }
    }

    static func dismantleNSView(_ container: KnowledgeGraphContainerNSView, coordinator: Coordinator) {
        container.webView.navigationDelegate = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Private

    private static func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        #endif
        return webView
    }

    private func loadGraphHTML(into webView: WKWebView) {
        guard let htmlURL = Bundle.main.url(
            forResource: "knowledge-graph",
            withExtension: "html",
            subdirectory: "WebRenderer"
        ) else {
            logger.error("WebRenderer/knowledge-graph.html not found in bundle")
            return
        }
        let directory = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: directory)
    }

    private func applyThemeCSS(_ css: String, to webView: WKWebView) {
        let escaped = css.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        webView.evaluateJavaScript("window.termuraGraph && window.termuraGraph.updateTheme(`\(escaped)`);") { _, error in
            if let error { logger.error("Graph theme update failed: \(error.localizedDescription)") }
        }
    }

    private func renderGraph(_ json: String, to webView: WKWebView) {
        let escaped = json.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        webView.evaluateJavaScript("window.termuraGraph && window.termuraGraph.render('\(escaped)');") { _, error in
            if let error { logger.error("Graph render failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var pendingGraphJSON: String?
        weak var webView: WKWebView?
        var onOpenNote: ((String) -> Void)?
        var onFilterTag: ((String) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard let json = pendingGraphJSON else { return }
            pendingGraphJSON = nil
            let escaped = json.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            webView.evaluateJavaScript("window.termuraGraph.render('\(escaped)');") { _, error in
                if let error { logger.error("Initial graph render failed: \(error.localizedDescription)") }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }

            if url.scheme == "termura-note" {
                handleNavigation(url)
                return .cancel
            }
            if url.isFileURL { return .allow }
            if url.absoluteString == "about:blank" { return .allow }
            return .cancel
        }

        private func handleNavigation(_ url: URL) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            switch url.host {
            case "open":
                if let title = components.queryItems?.first(where: { $0.name == "title" })?.value {
                    onOpenNote?(title)
                }
            case "filter-tag":
                if let tag = components.queryItems?.first(where: { $0.name == "tag" })?.value {
                    onFilterTag?(tag)
                }
            default:
                break
            }
        }
    }
}

// MARK: - Container

@MainActor
final class KnowledgeGraphContainerNSView: NSView {
    let webView: WKWebView
    var lastTheme: ThemeColors?
    var lastGraphJSON: String = ""

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("KnowledgeGraphContainerNSView must be instantiated programmatically")
    }

    override func layout() {
        super.layout()
        if webView.frame != bounds { webView.frame = bounds }
    }
}
