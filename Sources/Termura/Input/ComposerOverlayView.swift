import SwiftUI

/// Bottom sheet composer within the terminal area.
struct ComposerOverlayView: View {
    @ObservedObject var editorViewModel: EditorViewModel
    let editorHandle: EditorViewHandle
    let isNotesActive: Bool
    let onToggleNotes: () -> Void
    let onDismiss: () -> Void
    @Environment(\.themeManager) private var themeManager

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            editorArea
        }
        .overlay(alignment: .bottomTrailing) {
            sendButton
                .padding(.trailing, AppUI.Spacing.xxxxl)
                .padding(.bottom, AppUI.Spacing.xxl)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(themeManager.current.sidebarText.opacity(AppUI.Opacity.softBorder))
                .frame(height: 0.5)
        }
        .frame(height: AppConfig.UI.composerMaxHeight)
        .onAppear { focusEditor() }
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

    /// Notes toggle — uses onTapGesture instead of Button to avoid the macOS
    /// first-responder issue where a plain button ignores the first click when
    /// an NSTextView is the active first responder.
    private var notesToggleButton: some View {
        Image(systemName: isNotesActive
            ? "text.rectangle.fill" : "text.rectangle")
            .font(.system(size: 14))
            .foregroundColor(isNotesActive ? .accentColor : .secondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .onTapGesture { onToggleNotes() }
    }

    /// Dismiss button — same onTapGesture approach for consistency.
    private var dismissButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
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
        Button {
            editorViewModel.submit()
            onDismiss()
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(editorViewModel.currentText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - Focus

    private func focusEditor() {
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: AppConfig.UI.editorFocusDelayNanoseconds)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard let textView = editorHandle.textView,
                  let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }
}
