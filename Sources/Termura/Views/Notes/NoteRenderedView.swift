import AppKit
import OSLog
import SwiftUI
import WebKit

private let logger = Logger(subsystem: "com.termura.app", category: "NoteRenderedView")

/// SwiftUI wrapper around WKWebView for rendering a single markdown note.
/// Follows TerminalContainerView pattern: cache state in container, diff in updateNSView.
struct NoteRenderedView: NSViewRepresentable {
    let pool: any WebViewPoolProtocol
    let bridge: any WebRendererBridgeProtocol
    let theme: ThemeColors
    let markdown: String
    let references: [String]
    /// Titles of notes that contain a [[backlink]] pointing to this note.
    let backlinks: [String]
    /// Project root URL — used to resolve relative image paths in the markdown source.
    let projectURL: URL
    /// Called when a backlink (`[[note-name]]`) is clicked. The parameter is the target note title.
    var onOpenBacklink: ((String) -> Void)?

    func makeNSView(context: Context) -> NoteRenderedContainerNSView {
        let webView = pool.vend()
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = context.coordinator

        let container = NoteRenderedContainerNSView(webView: webView)
        container.lastAppliedTheme = theme
        container.lastAppliedMarkdown = ""
        container.lastAppliedReferences = []
        container.lastAppliedBacklinks = []

        let css = ThemeCSSGenerator.generate(from: theme)
        pool.applyThemeCSS(css, to: webView)

        // Schedule the initial markdown render after the WebView finishes loading index.html.
        // The Coordinator's didFinish callback triggers the first render.
        context.coordinator.pendingMarkdown = resolveImagePaths(markdown, baseURL: projectURL)
        context.coordinator.pendingReferences = references
        context.coordinator.pendingBacklinks = backlinks
        context.coordinator.bridge = bridge
        context.coordinator.webView = webView
        context.coordinator.onOpenBacklink = onOpenBacklink
        return container
    }

    func updateNSView(_ container: NoteRenderedContainerNSView, context: Context) {
        if container.lastAppliedTheme != theme {
            container.lastAppliedTheme = theme
            let css = ThemeCSSGenerator.generate(from: theme)
            pool.applyThemeCSS(css, to: container.webView)
        }
        let referencesChanged = container.lastAppliedReferences != references
        let backlinksChanged = container.lastAppliedBacklinks != backlinks
        if container.lastAppliedMarkdown != markdown || referencesChanged || backlinksChanged {
            container.lastAppliedMarkdown = markdown
            container.lastAppliedReferences = references
            container.lastAppliedBacklinks = backlinks
            let resolved = resolveImagePaths(markdown, baseURL: projectURL)
            let bridgeRef = bridge
            let webViewRef = container.webView
            let refs = references
            let bls = backlinks
            Task { @MainActor in
                await bridgeRef.renderMarkdown(resolved, references: refs, backlinks: bls, to: webViewRef)
            }
        }
    }

    static func dismantleNSView(_ container: NoteRenderedContainerNSView, coordinator: Coordinator) {
        container.webView.navigationDelegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Helpers

    /// Rewrites relative image paths in markdown to absolute file:// URLs so the WKWebView
    /// can load them. Bundle resources (renderer.js, vendor/) load via their own bundle URL.
    private func resolveImagePaths(_ source: String, baseURL: URL) -> String {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(
                pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#,
                options: []
            )
        } catch {
            logger.error("Failed to compile image path regex: \(error.localizedDescription)")
            return source
        }
        let nsSource = source as NSString
        let range = NSRange(location: 0, length: nsSource.length)
        let matches = regex.matches(in: source, options: [], range: range)
        guard !matches.isEmpty else { return source }

        var result = source
        // Walk matches in reverse to preserve earlier ranges while substituting.
        for match in matches.reversed() {
            guard match.numberOfRanges == 3 else { continue }
            let pathRange = match.range(at: 2)
            let altRange = match.range(at: 1)
            let pathString = nsSource.substring(with: pathRange)
            // Skip already-absolute URLs (http, https, file, data)
            if pathString.hasPrefix("http://")
                || pathString.hasPrefix("https://")
                || pathString.hasPrefix("file://")
                || pathString.hasPrefix("data:")
                || pathString.hasPrefix("/") {
                continue
            }
            let absoluteURL = baseURL.appendingPathComponent(pathString).standardized
            let altText = nsSource.substring(with: altRange)
            let replacement = "![\(altText)](\(absoluteURL.absoluteString))"
            let fullRange = match.range(at: 0)
            if let swiftRange = Range(fullRange, in: result) {
                result = result.replacingCharacters(in: swiftRange, with: replacement)
            }
        }
        return result
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var pendingMarkdown: String?
        var pendingReferences: [String] = []
        var pendingBacklinks: [String] = []
        weak var bridge: AnyObject?
        weak var webView: WKWebView?
        var onOpenBacklink: ((String) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard let markdown = pendingMarkdown else { return }
            pendingMarkdown = nil
            let refs = pendingReferences
            let bls = pendingBacklinks
            pendingReferences = []
            pendingBacklinks = []
            guard let bridge = bridge as? (any WebRendererBridgeProtocol) else { return }
            Task { @MainActor in
                await bridge.renderMarkdown(markdown, references: refs, backlinks: bls, to: webView)
            }
        }

        /// Block all navigation except local file:// URLs and `termura-note://` backlinks.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if url.scheme == "termura-note" {
                handleBacklink(url)
                return .cancel
            }
            if url.isFileURL { return .allow }
            if url.absoluteString == "about:blank" { return .allow }
            logger.debug("Blocked navigation: \(url.absoluteString)")
            return .cancel
        }

        private func handleBacklink(_ url: URL) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let title = components.queryItems?.first(where: { $0.name == "title" })?.value
            else { return }
            onOpenBacklink?(title)
        }
    }
}

// MARK: - Container NSView

/// Wraps the WKWebView and caches theme/markdown state for diff-only updates.
@MainActor
final class NoteRenderedContainerNSView: NSView {
    let webView: WKWebView
    var lastAppliedTheme: ThemeColors?
    var lastAppliedMarkdown: String = ""
    var lastAppliedReferences: [String] = []
    var lastAppliedBacklinks: [String] = []

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("NoteRenderedContainerNSView must be instantiated programmatically")
    }

    override func layout() {
        super.layout()
        if webView.frame != bounds {
            webView.frame = bounds
        }
    }
}
