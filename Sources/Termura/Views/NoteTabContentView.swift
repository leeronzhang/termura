import AppKit
import SwiftUI

/// Standalone view for the note-editor tab content.
///
/// Extracted from `MainView+Content.noteEditorView()` so the `.onChange` on
/// `notesViewModel.editingTitle` lives outside the `MainView+*.swift` context and
/// does not count against MainView's 5-onChange budget (CLAUDE.md §5.5).
struct NoteTabContentView: View {
    let noteID: NoteID
    @Environment(\.notesViewModel) var notesViewModel
    @Environment(\.themeManager) var themeManager
    @Environment(\.webViewPool) var webViewPool
    @Environment(\.webRendererBridge) var webRendererBridge
    var notes: Bindable<NotesViewModel>
    let onTitleChange: (NoteID, String) -> Void

    @FocusState private var isTitleFocused: Bool
    @State private var viewMode: NoteViewMode = .edit

    var body: some View {
        VStack(spacing: 0) {
            noteHeader
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Ensure notes are loaded before selecting — covers the startup tab-restore
            // scenario where this view appears before NotesSplitView triggers loadNotes().
            if notesViewModel.notes.isEmpty {
                await notesViewModel.loadNotes()
            }
            notesViewModel.selectNote(id: noteID)
            if notesViewModel.editingTitle == "Untitled" {
                isTitleFocused = true
            }
        }
        .onChange(of: notesViewModel.editingTitle) { _, newTitle in
            onTitleChange(noteID, newTitle)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewMode {
        case .edit:
            NoteEditorView(
                title: notesViewModel.editingTitle,
                filePath: notesViewModel.selectedNoteFilePath,
                text: notes.editingBody
            )
        case .reading:
            NoteRenderedView(
                pool: webViewPool,
                bridge: webRendererBridge,
                theme: themeManager.current,
                markdown: notesViewModel.editingBody,
                references: notesViewModel.selectedNote?.references ?? [],
                projectURL: notesViewModel.notesDirectoryURL
                    ?? URL(fileURLWithPath: AppConfig.Paths.homeDirectory)
            )
        }
    }

    private var noteHeader: some View {
        HStack(spacing: AppUI.Spacing.md) {
            TextField("Title", text: notes.editingTitle)
                .font(AppUI.Font.title1Semibold)
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
            Spacer()
            noteModeToggle
            noteFavoriteButton
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.top, AppUI.Spacing.md)
        .padding(.bottom, AppUI.Spacing.smMd)
    }

    private var noteModeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewMode = (viewMode == .edit) ? .reading : .edit
            }
        } label: {
            Image(systemName: viewMode == .edit ? "eye" : "pencil")
                .font(AppUI.Font.body)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(viewMode == .edit ? "Switch to Reading mode" : "Switch to Edit mode")
        .accessibilityLabel(viewMode == .edit ? "Switch to Reading mode" : "Switch to Edit mode")
    }

    private var noteFavoriteButton: some View {
        let isFav = notesViewModel.selectedNote?.isFavorite ?? false
        return Button {
            notesViewModel.toggleFavorite(id: noteID)
        } label: {
            Image(systemName: isFav ? "star.fill" : "star")
                .font(AppUI.Font.body)
                .foregroundColor(isFav ? .yellow : .secondary)
        }
        .buttonStyle(.plain)
        .help(isFav ? "Remove from favorites" : "Add to favorites")
        .accessibilityLabel(isFav ? "Remove from favorites" : "Add to favorites")
    }
}
