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
    var notes: Bindable<NotesViewModel>
    let onTitleChange: (NoteID, String) -> Void

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            noteHeader
            Divider()
            NoteEditorView(
                title: notesViewModel.editingTitle,
                text: notes.editingBody
            )
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

    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
            HStack(spacing: AppUI.Spacing.md) {
                TextField("Title", text: notes.editingTitle)
                    .font(AppUI.Font.title1Semibold)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                Spacer()
                noteFavoriteButton
            }
            if let filePath = notesViewModel.selectedNoteFilePath {
                Button {
                    NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                } label: {
                    Text(filePath)
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.top, AppUI.Spacing.md)
        .padding(.bottom, AppUI.Spacing.smMd)
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
