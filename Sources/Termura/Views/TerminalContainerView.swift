// Exemption: This is the ONLY file permitted to import SwiftTerm in the Views layer.
// The NSViewRepresentable boundary is explicitly required by the architecture.
import AppKit
import OSLog
import SwiftTerm
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalContainerView")

/// NSViewRepresentable wrapper around SwiftTerm's LocalProcessTerminalView.
/// Acts as the bridge between SwiftUI layout and the AppKit terminal renderer.
/// Returns a TerminalDragContainerView so that drag-and-drop is handled by a real
/// NSDraggingDestination override rather than a disconnected Coordinator.
struct TerminalContainerView: NSViewRepresentable {
    let viewModel: TerminalViewModel
    let engine: any TerminalEngine
    let theme: ThemeColors
    /// Value types so SwiftUI diffs trigger updateNSView on change.
    let fontFamily: String
    let fontSize: CGFloat
    /// When true, hitTest returns nil so that NSWindow falls back to the NSHostingView
    /// and SwiftUI gesture targets (backdrop, composer header buttons) receive events.
    var isComposerActive: Bool = false

    func makeNSView(context: Context) -> TerminalDragContainerView {
        let termView = engine.terminalNSView
        termView.autoresizingMask = [.width, .height]
        if let tv = termView as? LocalProcessTerminalView {
            applyTheme(theme, to: tv)
        }
        hideScroller(in: termView)
        let container = TerminalDragContainerView(terminalView: termView)
        // Seed the font cache so the first updateNSView call skips the redundant font assignment.
        container.lastAppliedFontName = fontFamily
        container.lastAppliedFontSize = fontSize
        container.dragHandler = { [weak viewModel] paths in
            viewModel?.send(paths)
        }
        return container
    }

    func updateNSView(_ container: TerminalDragContainerView, context: Context) {
        container.isPassthrough = isComposerActive
        guard let termView = container.terminalView as? LocalProcessTerminalView else { return }
        // Colors are cheap to set — always apply so theme switches take effect immediately.
        applyColors(theme, to: termView)
        // Font assignment is expensive: SwiftTerm recalculates character dimensions for every cell.
        // Guard to avoid triggering this on every parent re-render (ViewModel @Published changes
        // cause frequent re-renders — without this guard, CPU spikes even when idle).
        let fontChanged = container.lastAppliedFontName != fontFamily
            || container.lastAppliedFontSize != fontSize
        if fontChanged {
            applyFont(to: termView)
            container.lastAppliedFontName = fontFamily
            container.lastAppliedFontSize = fontSize
        }
        hideScroller(in: termView)
    }

    // MARK: - Theme application

    private func applyColors(_ theme: ThemeColors, to view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = NSColor(theme.background)
        view.nativeForegroundColor = NSColor(theme.foreground)
        view.installColors(theme.toSwiftTermColors())
    }

    private func applyFont(to view: LocalProcessTerminalView) {
        let font = NSFont(name: fontFamily, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.font = font
        logger.debug("Terminal font set: \(font.fontName) size=\(fontSize)")
    }

    private func applyTheme(_ theme: ThemeColors, to view: LocalProcessTerminalView) {
        applyColors(theme, to: view)
        applyFont(to: view)
    }

    /// Hides the legacy NSScroller that SwiftTerm adds directly as a subview.
    /// The scroller track is always visible with `.legacy` style, even when disabled,
    /// causing a lighter vertical strip at the terminal view's right edge.
    private func hideScroller(in view: NSView) {
        for sub in view.subviews where sub is NSScroller {
            sub.isHidden = true
        }
    }
}

// MARK: - TerminalDragContainerView

/// Container NSView wrapping the SwiftTerm terminal view.
/// Implements NSDraggingDestination directly — this is required because NSView subclasses
/// must override drag methods themselves; there is no drag delegate protocol.
///
/// Supports:
///   - File URL drops: shell-escapes the path and sends it to the terminal.
///   - Image drops (PNG/TIFF from screenshots, browsers, Preview): saves a temporary
///     PNG to ~/.termura/tmp/ and sends the escaped path.
@MainActor
final class TerminalDragContainerView: NSView {
    let terminalView: NSView
    var dragHandler: ((String) -> Void)?
    /// Set to true while the composer overlay is visible so that hitTest returns nil,
    /// letting AppKit fall through to NSHostingView and SwiftUI handle events.
    var isPassthrough = false
    /// Last font family/size applied via updateNSView. Guards against SwiftTerm
    /// recalculating character dimensions on every parent view re-render.
    var lastAppliedFontName: String?
    var lastAppliedFontSize: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        isPassthrough ? nil : super.hitTest(point)
    }

    init(terminalView: NSView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)
        registerForDraggedTypes([.fileURL, .URL, .tiff, .png])
    }

    required init?(coder: NSCoder) {
        logger.fault("TerminalDragContainerView must be instantiated programmatically, not via Interface Builder")
        return nil
    }

    override func layout() {
        super.layout()
        terminalView.frame = bounds
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        let hasFileURL = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
        return (hasFileURL || hasImage) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path.shellEscaped).joined(separator: " ")
            dragHandler?(paths)
            return true
        }
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            do {
                let url = try saveTemporaryImage(image)
                dragHandler?(url.path.shellEscaped)
                return true
            } catch {
                logger.error("Failed to save dropped image: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }

    // MARK: - Private

    private func saveTemporaryImage(_ image: NSImage) throws -> URL {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let tmpDir = homeURL.appendingPathComponent(AppConfig.DragDrop.tempImageSubdirectory)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let name = "\(AppConfig.DragDrop.imagePastePrefix)-\(Int(Date().timeIntervalSince1970)).\(AppConfig.DragDrop.imagePasteExtension)"
        let fileURL = tmpDir.appendingPathComponent(name)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw ImageSaveError.conversionFailed
        }
        try png.write(to: fileURL)
        return fileURL
    }
}

private enum ImageSaveError: Error {
    case conversionFailed
}
