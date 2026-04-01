import AppKit
import SwiftUI

/// Bottom sheet composer within the terminal area.
struct ComposerOverlayView: View {
    var editorViewModel: EditorViewModel
    let editorHandle: EditorViewHandle
    let isNotesActive: Bool
    let onToggleNotes: () -> Void
    let onDismiss: () -> Void
    @Environment(\.themeManager) private var themeManager
    @State private var isMounted = false

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            editorArea
        }
        .overlay(alignment: .bottomTrailing) {
            sendButton
                .padding(.trailing, AppUI.Spacing.xxl + AppUI.Spacing.xxl)
                .padding(.bottom, AppUI.Spacing.xxl)
        }
        .overlay(alignment: .bottomLeading) {
            AttachmentBarView(editorViewModel: editorViewModel)
                .padding(.leading, AppUI.Spacing.xxl + AppUI.Spacing.xxl)
                .padding(.bottom, AppUI.Spacing.xxl)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(themeManager.current.sidebarText.opacity(AppUI.Opacity.softBorder))
                .frame(height: 0.5)
        }
        .frame(height: AppConfig.UI.composerMaxHeight)
        .onAppear {
            isMounted = true
            focusEditor()
        }
        .onDisappear {
            isMounted = false
        }
    }

    // MARK: - Header (notes toggle left, close right)

    private var cardHeader: some View {
        HStack {
            notesToggleButton
            Spacer()
            dismissButton
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.top, AppUI.Spacing.lgXl)
        .padding(.bottom, AppUI.Spacing.sm)
    }

    /// Notes toggle — backed by a real AppKit NSView overlay so that mouse events
    /// are routed directly by AppKit's hitTest, bypassing SwiftUI gesture conflicts
    /// caused by NSViewRepresentable views (SwiftTerm, NSTextView) in the same
    /// NSHostingView hierarchy intercepting events at a lower Z-order.
    private var notesToggleButton: some View {
        Image(systemName: isNotesActive
            ? "text.rectangle.fill" : "text.rectangle")
            .font(AppUI.Font.title2Regular)
            .foregroundColor(isNotesActive ? .accentColor : .secondary)
            .frame(width: 32, height: 32)
            .overlay(AppKitClickableOverlay(action: onToggleNotes))
    }

    /// Dismiss button — same AppKit overlay approach as notesToggleButton.
    private var dismissButton: some View {
        Image(systemName: "xmark")
            .font(AppUI.Font.title3Medium)
            .foregroundColor(.secondary)
            .frame(width: 32, height: 32)
            .overlay(AppKitClickableOverlay(action: onDismiss))
    }

    // MARK: - Editor

    private var editorArea: some View {
        EditorInputView(viewModel: editorViewModel, viewHandle: editorHandle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(.horizontal, AppUI.Spacing.xxl)
            .padding(.vertical, AppUI.Spacing.sm)
    }

    // MARK: - Floating Send

    private var sendButton: some View {
        let hasContent = !editorViewModel.currentText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !editorViewModel.attachments.isEmpty
        return Image(systemName: "paperplane.fill")
            .font(AppUI.Font.title2Regular)
            .foregroundColor(hasContent ? .white : Color.white.opacity(0.4))
            .frame(width: 36, height: 36)
            .background(Circle().fill(hasContent ? Color.accentColor : Color.secondary.opacity(0.4)))
            .shadow(color: .black.opacity(hasContent ? 0.3 : 0), radius: 4, y: 2)
            .overlay(AppKitClickableOverlay(action: {
                let hasText = !editorViewModel.currentText
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                guard hasText || !editorViewModel.attachments.isEmpty else { return }
                editorViewModel.submit()
            }))
    }

    // MARK: - Focus

    private func focusEditor() {
        Task { @MainActor in
            do {
                try await Task.sleep(for: AppConfig.UI.editorFocusDelay)
            } catch is CancellationError {
                // CancellationError is expected — parent task was cancelled (e.g. view dismissed).
                return
            }
            guard isMounted else { return }
            guard let textView = editorHandle.textView,
                  let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }
}

// MARK: - AppKit click overlay

/// NSViewRepresentable that places a transparent AppKit NSView over a SwiftUI view.
/// Mouse events (mouseDown/mouseUp) are handled directly in AppKit, completely
/// bypassing SwiftUI's gesture recognition system.
///
/// Why this is needed: TerminalDragContainerView (SwiftTerm) and EditorTextView
/// (NSScrollView) are real NSViews in the same NSHostingView hierarchy. AppKit's
/// hitTest finds them by Z-order before NSHostingView can route events to SwiftUI
/// gestures. By placing this NSView AFTER those views in the subview order (later
/// declared = higher Z), AppKit routes the click here first.
///
/// Used by: ComposerOverlayView (header buttons, send button) and
/// TerminalAreaView (composer backdrop) — any SwiftUI tap target that overlaps
/// a SwiftTerm or NSTextView NSView must use this instead of .onTapGesture.
struct AppKitClickableOverlay: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> AppKitClickableNSView {
        let view = AppKitClickableNSView()
        view.clickHandler = action
        return view
    }

    func updateNSView(_ nsView: AppKitClickableNSView, context: Context) {
        nsView.clickHandler = action
    }
}

@MainActor
final class AppKitClickableNSView: NSView {
    var clickHandler: (() -> Void)?

    /// Accept first mouse so the button works even when the window is not yet key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Consume the mouseDown to start tracking; do not call super so the event
    /// does not propagate further up the responder chain.
    override func mouseDown(with event: NSEvent) {}

    /// Fire the action on mouseUp, confirming the click stayed within bounds.
    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.contains(loc) else { return }
        clickHandler?()
    }
}
