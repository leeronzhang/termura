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
        let composerActive = commandRouter.showComposer
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: AppUI.Spacing.sm) {
                ForEach(vm.notes) { note in
                    SidebarNoteRow(
                        note: note,
                        isActive: vm.selectedNoteID == note.id,
                        composerActive: composerActive,
                        onOpen: { onOpenNote?(note.id, note.title) },
                        onInsert: { commandRouter.composerInsertHandler?($0) },
                        onToggleFavorite: { vm.toggleFavorite(id: note.id) }
                    )
                    .contextMenu {
                        Button {
                            vm.toggleFavorite(id: note.id)
                        } label: {
                            Text(note.isFavorite ? "Unfavorite" : "Favorite")
                        }
                        Button("Delete", role: .destructive) {
                            Task { await vm.deleteNote(id: note.id) }
                        }
                    }
                }
            }
            .padding(.horizontal, AppUI.Spacing.lg)
        }
    }
}

// MARK: - Note Row (owns hover state)

/// Standalone row view for sidebar notes. Owns `@State isHovered` for
/// composer-aware insert button that appears on mouse hover.
private struct SidebarNoteRow: View {
    let note: NoteRecord
    let isActive: Bool
    let composerActive: Bool
    let onOpen: () -> Void
    let onInsert: (String) -> Void
    let onToggleFavorite: () -> Void
    @Environment(\.themeManager) private var themeManager

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: AppUI.Spacing.smMd) {
            favoriteIcon
                .padding(.top, AppUI.Spacing.xxs)
            VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
                HStack {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(isActive ? AppUI.Font.title3Medium : AppUI.Font.title3)
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(formattedDate(note.updatedAt))
                        .font(AppUI.Font.micro)
                        .foregroundColor(.secondary)
                }
                if let preview = notePreview(note.body) {
                    Text(preview)
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary.opacity(AppUI.Opacity.secondary))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
        .overlay(alignment: .trailing) {
            if isHovered && composerActive { insertButton.padding(.trailing, AppUI.Spacing.lg) }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppUI.Radius.md)
                .stroke(isActive ? Color.accentColor.opacity(AppUI.Opacity.border) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { rowTapped() }
        .onHover { isHovered = $0 }
        .draggable(note.body)
    }

    private func rowTapped() {
        if composerActive {
            onInsert(note.body)
        } else {
            onOpen()
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: AppUI.Radius.md)
            .fill(isActive ? Color.accentColor.opacity(AppUI.Opacity.selected) : .clear)
    }

    private var insertButton: some View {
        Button {
            onInsert(note.body)
        } label: {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .help("Insert into Composer")
        .transition(.opacity)
    }

    private var favoriteIcon: some View {
        Button { onToggleFavorite() } label: {
            Image(systemName: note.isFavorite ? "star.fill" : "star")
                .font(.system(size: 11))
                .foregroundColor(note.isFavorite ? .yellow : .secondary)
        }
        .buttonStyle(.plain)
        .help(note.isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    // MARK: - Helpers

    private func notePreview(_ body: String) -> String? {
        let line = body.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let line, !line.isEmpty else { return nil }
        let limit = AppConfig.Search.previewLength
        return line.count > limit ? String(line.prefix(limit)) + "..." : line
    }

    private func formattedDate(_ date: Date) -> String {
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
