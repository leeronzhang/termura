import SwiftUI

// MARK: - Notes Tab

extension SidebarView {
    @ViewBuilder
    var notesContent: some View {
        VStack(spacing: 0) {
            notesHeader(vm: notesViewModel)
            notesList(vm: notesViewModel)
        }
        .task { await notesViewModel.loadNotes() }
    }

    func notesHeader(vm: NotesViewModel) -> some View {
        HStack {
            Text("Notes")
                .panelHeaderStyle()
            Spacer()
            Button { vm.createNote() } label: {
                Image(systemName: "plus")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    func notesList(vm: NotesViewModel) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(vm.notes) { note in
                    noteRow(note: note, isActive: vm.selectedNoteID == note.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                vm.deleteNote(id: note.id)
                            }
                        }
                }
            }
            .padding(.horizontal, AppUI.Spacing.lg)
        }
    }

    func noteRow(note: NoteRecord, isActive: Bool) -> some View {
        Button {
            onOpenNote?(note.id, note.title)
        } label: {
            HStack(spacing: AppUI.Spacing.md) {
                FileTypeIcon.image(for: "note.md")
                    .resizable()
                    .scaledToFit()
                    .frame(width: AppUI.Size.fileTypeIcon, height: AppUI.Size.fileTypeIcon)
                    .foregroundColor(.secondary)
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(isActive ? AppUI.Font.title3Medium : AppUI.Font.title3)
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, AppUI.Spacing.lg)
            .padding(.vertical, AppUI.Spacing.smMd)
            .background(
                isActive
                    ? Color.accentColor.opacity(AppUI.Opacity.selected)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AppUI.Radius.md)
                    .stroke(isActive ? Color.accentColor.opacity(AppUI.Opacity.border) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
