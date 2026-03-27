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
            LazyVStack(spacing: AppUI.Spacing.xxs) {
                ForEach(vm.notes) { note in
                    noteRow(note: note, isActive: vm.selectedNoteID == note.id)
                        .contextMenu {
                            Button {
                                vm.toggleFavorite(id: note.id)
                            } label: {
                                Text(note.isFavorite ? "Unfavorite" : "Favorite")
                            }
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
            HStack(alignment: .top, spacing: AppUI.Spacing.md) {
                FileTypeIcon.image(for: "note.md")
                    .resizable()
                    .scaledToFit()
                    .frame(width: AppUI.Size.fileTypeIcon, height: AppUI.Size.fileTypeIcon)
                    .foregroundColor(.secondary)
                    .padding(.top, AppUI.Spacing.xxs)

                VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
                    HStack(spacing: AppUI.Spacing.smMd) {
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(isActive ? AppUI.Font.title3Medium : AppUI.Font.title3)
                            .foregroundColor(isActive ? .primary : .secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(sidebarFormattedDate(note.updatedAt))
                            .font(AppUI.Font.micro)
                            .foregroundColor(.secondary)
                    }

                    if let preview = sidebarNotePreview(note.body) {
                        Text(preview)
                            .font(AppUI.Font.caption)
                            .foregroundColor(.secondary.opacity(AppUI.Opacity.secondary))
                            .lineLimit(1)
                    }
                }

                favoriteButton(note: note)
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

    // MARK: - Private Helpers

    private func favoriteButton(note: NoteRecord) -> some View {
        Button {
            notesViewModel.toggleFavorite(id: note.id)
        } label: {
            Image(systemName: note.isFavorite ? "star.fill" : "star")
                .font(.system(size: 11))
                .foregroundColor(
                    note.isFavorite
                        ? .yellow
                        : .secondary.opacity(AppUI.Opacity.tertiary)
                )
        }
        .buttonStyle(.plain)
        .help(note.isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private func sidebarNotePreview(_ body: String) -> String? {
        let line = body.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let line, !line.isEmpty else { return nil }
        let limit = AppConfig.Search.previewLength
        return line.count > limit ? String(line.prefix(limit)) + "..." : line
    }

    private func sidebarFormattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
