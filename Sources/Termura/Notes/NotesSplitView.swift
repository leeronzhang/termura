import AppKit
import SwiftUI

struct NotesSplitView: View {
    @Bindable var viewModel: NotesViewModel

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HSplitView {
            noteList
                .frame(minWidth: 180, maxWidth: 260)
            editorPane
                .frame(minWidth: 300, maxWidth: .infinity)
        }
        .task { await viewModel.loadNotes() }
    }

    // MARK: - Note list

    private var noteList: some View {
        VStack(spacing: 0) {
            noteListHeader
            List(viewModel.notes, selection: $viewModel.selectedNoteID) { note in
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .tag(note.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.deleteNote(id: note.id) }
                        }
                    }
            }
            .listStyle(.sidebar)
            .onChange(of: viewModel.selectedNoteID) { _, newID in
                if let id = newID {
                    viewModel.selectNote(id: id)
                    if viewModel.editingTitle == "Untitled" {
                        isTitleFocused = true
                    }
                }
            }
        }
    }

    private var noteListHeader: some View {
        HStack {
            Text("Notes")
                .panelHeaderStyle()
            Spacer()
            Button {
                viewModel.createNote()
            } label: {
                Image(systemName: "plus").font(AppUI.Font.body)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorPane: some View {
        if let noteID = viewModel.selectedNoteID {
            VStack(spacing: 0) {
                noteHeader(noteID: noteID)
                Divider()
                NoteEditorView(
                    title: viewModel.editingTitle,
                    filePath: viewModel.selectedNoteFilePath,
                    text: $viewModel.editingBody
                )
                .id(noteID)
            }
        } else {
            VStack(spacing: AppUI.Spacing.smMd) {
                Image(systemName: "text.rectangle")
                    .font(AppUI.Font.hero)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
                Text("Select or create a note")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func noteHeader(noteID: NoteID) -> some View {
        HStack(spacing: AppUI.Spacing.md) {
            TextField("Title", text: $viewModel.editingTitle)
                .font(AppUI.Font.title1Semibold)
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
            Spacer()
            splitFavoriteButton(noteID: noteID)
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.top, AppUI.Spacing.md)
        .padding(.bottom, AppUI.Spacing.smMd)
    }

    private func splitFavoriteButton(noteID: NoteID) -> some View {
        let isFav = viewModel.selectedNote?.isFavorite ?? false
        return Button {
            viewModel.toggleFavorite(id: noteID)
        } label: {
            Image(systemName: isFav ? "star.fill" : "star")
                .font(AppUI.Font.body)
                .foregroundColor(isFav ? .yellow : .secondary)
        }
        .buttonStyle(.plain)
        .help(isFav ? "Remove from favorites" : "Add to favorites")
    }
}
