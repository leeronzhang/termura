import SwiftUI

/// Bottom sheet composer within the terminal area.
struct ComposerOverlayView: View {
    @ObservedObject var editorViewModel: EditorViewModel
    var notesViewModel: NotesViewModel
    let editorHandle: EditorViewHandle
    let onDismiss: () -> Void
    @Environment(\.themeManager) private var themeManager

    @State private var showNotes = false
    @State private var noteSearch: String = ""
    @State private var showSaveConfirm = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: editor area with header and floating send
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    cardHeader
                    editorArea
                }
                sendButton
                    .padding(.trailing, AppUI.Spacing.xxxxl)
                    .padding(.bottom, AppUI.Spacing.xxl)
            }

            if showNotes {
                Divider()
                notesPanel
                    .frame(width: AppConfig.UI.composerNotesPanelWidth)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(themeManager.current.sidebarText.opacity(AppUI.Opacity.softBorder))
                .frame(height: 0.5)
        }
        .frame(height: AppConfig.UI.composerMaxHeight)
        .task { await notesViewModel.loadNotes() }
        .onAppear { focusEditor() }
    }

    // MARK: - Header (notes icon + close)

    private var cardHeader: some View {
        HStack(spacing: AppUI.Spacing.lgXl) {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
                    showNotes.toggle()
                }
            } label: {
                Image(systemName: showNotes ? "text.rectangle.fill" : "text.rectangle")
                    .font(.system(size: 13))
                    .foregroundColor(showNotes ? .accentColor : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Notes")

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.top, AppUI.Spacing.lgXl)
        .padding(.bottom, AppUI.Spacing.sm)
    }

    // MARK: - Editor

    private var editorArea: some View {
        EditorInputView(viewModel: editorViewModel, viewHandle: editorHandle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Notes Panel

    private var notesPanel: some View {
        ComposerNotesListView(
            editorViewModel: editorViewModel,
            notesViewModel: notesViewModel,
            noteSearch: $noteSearch,
            onSelectNote: { focusEditor() },
            onDismiss: onDismiss
        )
    }

    // MARK: - Focus

    private func focusEditor() {
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: AppConfig.UI.editorFocusDelayNanoseconds)
            } catch is CancellationError {
                return
            } catch {
                // Non-critical: focus is cosmetic; user can click the editor manually.
                return
            }
            guard let textView = editorHandle.textView,
                  let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }
}
