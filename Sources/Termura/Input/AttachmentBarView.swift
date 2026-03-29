import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.termura.app", category: "AttachmentBarView")

// MARK: - AttachmentBarView

/// Bottom toolbar within the Composer showing the attachment + button and queued attachment pills.
struct AttachmentBarView: View {
    @ObservedObject var editorViewModel: EditorViewModel

    var body: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            addMenuButton
            if !editorViewModel.attachments.isEmpty {
                attachmentPillRow
                    .frame(maxWidth: 280)
            }
        }
    }

    // MARK: - Add button

    private var isAtLimit: Bool {
        editorViewModel.attachments.count >= AppConfig.Attachments.maxCount
    }

    private var addMenuButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppConfig.UI.attachmentPillCornerRadius)
                .fill(Color.secondary.opacity(AppUI.Opacity.highlight))
                .frame(width: 28, height: 28)
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isAtLimit ? Color.secondary.opacity(AppUI.Opacity.tertiary) : Color.secondary)
            if !isAtLimit {
                AppKitMenuOverlay(menuProvider: menuItems)
            }
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - Pill row

    private var attachmentPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppUI.Spacing.sm) {
                ForEach(editorViewModel.attachments) { att in
                    AttachmentPillView(attachment: att) {
                        editorViewModel.removeAttachment(id: att.id)
                    }
                }
            }
            .padding(.vertical, AppUI.Spacing.xs)
        }
    }

    // MARK: - Menu items

    private var menuItems: [AppKitMenuOverlay.MenuItem] {
        let remaining = AppConfig.Attachments.maxCount - editorViewModel.attachments.count
        return [
            AppKitMenuOverlay.MenuItem(title: "Image") { [weak editorViewModel] in
                guard let vm = editorViewModel else { return }
                AttachmentFilePicker.pickImages(remaining: remaining) { urls in
                    urls.forEach { vm.addAttachment($0, kind: .image, isTemporary: false) }
                }
            },
            AppKitMenuOverlay.MenuItem(title: "File") { [weak editorViewModel] in
                guard let vm = editorViewModel else { return }
                AttachmentFilePicker.pickFiles(remaining: remaining) { urls in
                    urls.forEach { vm.addAttachment($0, kind: .textFile, isTemporary: false) }
                }
            },
            AppKitMenuOverlay.MenuItem(title: "Paste from Clipboard") { [weak editorViewModel] in
                guard let vm = editorViewModel else { return }
                AttachmentFilePicker.pasteFromClipboard { url in
                    vm.addAttachment(url, kind: .image, isTemporary: true)
                }
            }
        ]
    }
}

// MARK: - AttachmentPillView

private struct AttachmentPillView: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: AppUI.Spacing.xs) {
            Image(systemName: attachment.symbolName)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(attachment.displayName)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
            ZStack {
                Color.clear.frame(width: 16, height: 16)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                AppKitClickableOverlay(action: onRemove)
            }
            .frame(width: 16, height: 16)
        }
        .padding(.horizontal, AppUI.Spacing.md)
        .padding(.vertical, AppUI.Spacing.xs)
        .frame(height: AppConfig.UI.attachmentPillHeight)
        .background(
            RoundedRectangle(cornerRadius: AppConfig.UI.attachmentPillCornerRadius)
                .fill(Color.secondary.opacity(AppUI.Opacity.highlight))
        )
    }
}

// MARK: - AppKitMenuOverlay

/// Transparent AppKit NSView overlay that shows an NSMenu on click.
/// Uses the same pattern as AppKitClickableOverlay to reliably receive mouse events
/// in an NSHostingView hierarchy that contains NSScrollView/NSTextView subviews.
struct AppKitMenuOverlay: NSViewRepresentable {
    struct MenuItem {
        let title: String
        let action: () -> Void
    }

    let menuProvider: [MenuItem]

    func makeNSView(context: Context) -> AppKitMenuNSView {
        let view = AppKitMenuNSView()
        view.menuItems = menuProvider
        return view
    }

    func updateNSView(_ nsView: AppKitMenuNSView, context: Context) {
        nsView.menuItems = menuProvider
    }
}

@MainActor
final class AppKitMenuNSView: NSView {
    var menuItems: [AppKitMenuOverlay.MenuItem] = []
    // Strong references to action proxies — NSMenu items hold weak refs to target.
    private var actionProxies: [MenuActionProxy] = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.contains(loc) else { return }
        showMenu()
    }

    private func showMenu() {
        let menu = NSMenu()
        actionProxies = menuItems.map { item in
            let proxy = MenuActionProxy(action: item.action)
            let menuItem = NSMenuItem(title: item.title, action: #selector(MenuActionProxy.fire), keyEquivalent: "")
            menuItem.target = proxy
            menu.addItem(menuItem)
            return proxy
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
    }
}

// MARK: - MenuActionProxy

/// Bridges NSMenuItem's target/action ObjC pattern to a Swift closure.
@MainActor
private final class MenuActionProxy: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

// MARK: - AttachmentFilePicker

/// Encapsulates NSOpenPanel and NSPasteboard interactions for the attachment bar.
@MainActor
private enum AttachmentFilePicker {
    static func pickImages(remaining: Int, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .heic, .heif]
        panel.title = "Choose Images"
        present(panel, remaining: remaining, completion: completion)
    }

    static func pickFiles(remaining: Int, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.text, .sourceCode, .plainText, .utf8PlainText, .json, .xml]
        panel.title = "Choose Files"
        present(panel, remaining: remaining, completion: completion)
    }

    static func pasteFromClipboard(completion: @escaping (URL) -> Void) {
        guard let image = NSImage(pasteboard: .general) else { return }
        do {
            let url = try saveTemporaryAttachmentImage(image)
            completion(url)
        } catch {
            logger.error("Clipboard paste failed: \(error.localizedDescription)")
        }
    }

    private static func present(
        _ panel: NSOpenPanel,
        remaining: Int,
        completion: @escaping ([URL]) -> Void
    ) {
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            completion(Array(panel.urls.prefix(remaining)))
        }
    }
}
