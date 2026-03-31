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
            HStack(spacing: AppUI.Spacing.md) {
                TextField("Title", text: notes.editingTitle)
                    .font(AppUI.Font.title1Semibold)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                Spacer()
                noteFavoriteButton
            }
            .padding(.horizontal, AppUI.Spacing.xl)
            .padding(.top, AppUI.Spacing.xl)
            .padding(.bottom, AppUI.Spacing.md)
            Divider()
            NoteEditorView(
                title: notesViewModel.editingTitle,
                text: notes.editingBody
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            notesViewModel.selectNote(id: noteID)
            if notesViewModel.editingTitle == "Untitled" {
                isTitleFocused = true
            }
        }
        .onChange(of: notesViewModel.editingTitle) { _, newTitle in
            onTitleChange(noteID, newTitle)
        }
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
