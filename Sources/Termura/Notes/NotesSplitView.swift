import SwiftUI

struct NotesSplitView: View {
    @ObservedObject var viewModel: NotesViewModel

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
                            viewModel.deleteNote(id: note.id)
                        }
                    }
            }
            .listStyle(.sidebar)
            .onChange(of: viewModel.selectedNoteID) { _, newID in
                if let id = newID { viewModel.selectNote(id: id) }
            }
        }
    }

    private var noteListHeader: some View {
        HStack {
            Text("Notes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
            Button {
                viewModel.createNote()
            } label: {
                Image(systemName: "plus").font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorPane: some View {
        if viewModel.selectedNoteID != nil {
            VStack(spacing: 0) {
                TextField("Title", text: $viewModel.editingTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                Divider()
                NoteEditorView(
                    title: viewModel.editingTitle,
                    text: $viewModel.editingBody
                )
            }
        } else {
            Text("Select or create a note")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
