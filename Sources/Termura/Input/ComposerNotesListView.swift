import SwiftUI

/// Notes list panel for the Composer — browse and select notes to fill the editor.
struct ComposerNotesListView: View {
    @ObservedObject var editorViewModel: EditorViewModel
    var notesViewModel: NotesViewModel
    @Binding var noteSearch: String
    let onSelectNote: () -> Void
    let onDismiss: () -> Void

    @State private var isSearchExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Divider().padding(.horizontal, AppUI.Spacing.lg)
            noteList
        }
    }

    // MARK: - Search

    private var searchRow: some View {
        HStack(spacing: AppUI.Spacing.smMd) {
            Button {
                withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
                    isSearchExpanded.toggle()
                    if !isSearchExpanded { noteSearch = "" }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(AppUI.Font.label)
                    .foregroundColor(isSearchExpanded ? .accentColor : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSearchExpanded {
                TextField("Search notes", text: $noteSearch)
                    .textFieldStyle(.plain)
                    .font(AppUI.Font.body)
            }
        }
        .padding(.horizontal, AppUI.Spacing.lgXl)
        .padding(.vertical, AppUI.Spacing.smMd)
    }

    // MARK: - Note List

    private var noteList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if filteredNotes.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: AppUI.Spacing.xs) {
                    ForEach(filteredNotes) { note in
                        noteRow(note)
                    }
                }
                .padding(.horizontal, AppUI.Spacing.lg)
                .padding(.vertical, AppUI.Spacing.md)
            }
        }
    }

    private var filteredNotes: [NoteRecord] {
        let base: [NoteRecord]
        if noteSearch.isEmpty {
            base = notesViewModel.notes
        } else {
            let query = noteSearch.lowercased()
            base = notesViewModel.notes.filter {
                $0.title.lowercased().contains(query) || $0.body.lowercased().contains(query)
            }
        }
        // Favorites first, then by updatedAt (already sorted from repository)
        return base.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func noteRow(_ note: NoteRecord) -> some View {
        HStack(spacing: AppUI.Spacing.smMd) {
            Button {
                editorViewModel.updateText(note.body)
                notesViewModel.selectNote(id: note.id)
                onSelectNote()
            } label: {
                VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(AppUI.Font.labelMedium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(formattedDate(note.updatedAt))
                        .font(AppUI.Font.micro)
                        .foregroundColor(.secondary)

                    if !note.body.isEmpty {
                        Text(notePreview(note.body))
                            .font(AppUI.Font.captionMono)
                            .foregroundColor(.secondary.opacity(AppUI.Opacity.secondary))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                notesViewModel.toggleFavorite(id: note.id)
            } label: {
                Image(systemName: note.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundColor(note.isFavorite ? .yellow : .secondary.opacity(AppUI.Opacity.tertiary))
            }
            .buttonStyle(.plain)
            .help(note.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.smMd)
        .background(Color.secondary.opacity(AppUI.Opacity.whisper))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: AppUI.Spacing.md) {
            Image(systemName: "note.text")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
            Text("No notes yet")
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
            Text("Notes you create will appear here")
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppUI.Spacing.xxxxl)
    }

    // MARK: - Formatting

    private func notePreview(_ body: String) -> String {
        let line = body.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? body
        let limit = AppConfig.Search.previewLength
        return line.count > limit ? String(line.prefix(limit)) + "..." : line
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
}
