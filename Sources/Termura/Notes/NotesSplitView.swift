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
        if viewModel.selectedNoteID != nil {
            VStack(spacing: 0) {
                TextField("Title", text: $viewModel.editingTitle)
                    .font(AppUI.Font.title1Semibold)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, AppUI.Spacing.xl)
                    .padding(.top, AppUI.Spacing.xl)
                    .padding(.bottom, AppUI.Spacing.md)
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
