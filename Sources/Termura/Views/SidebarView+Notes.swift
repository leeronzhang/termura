import SwiftUI

// MARK: - Notes Tab

extension SidebarView {
    @ViewBuilder
    var notesContent: some View {
        VStack(spacing: 0) {
            notesHeader(vm: notesViewModel)
            switch notesViewModel.notesBrowseMode {
            case .list:
                if !notesViewModel.allTags.isEmpty {
                    TagChipsBar(
                        tags: notesViewModel.allTags,
                        selectedTag: notesViewModel.selectedTagFilter,
                        onSelect: { notesViewModel.selectedTagFilter = $0 }
                    )
                }
                notesList(vm: notesViewModel)
            case .graph:
                notesGraphView
            }
        }
        .task { await notesViewModel.loadNotes() }
    }

    private var notesGraphView: some View {
        KnowledgeGraphView(
            theme: themeManager.current,
            graphJSON: notesViewModel.knowledgeGraphJSON,
            onOpenNote: { title in
                guard let note = notesViewModel.findNote(byTitle: title) else { return }
                notesViewModel.notesBrowseMode = .list
                onOpenNote?(note.id, note.title)
            },
            onFilterTag: { tag in
                notesViewModel.selectedTagFilter = tag
                notesViewModel.notesBrowseMode = .list
            }
        )
    }

    func notesHeader(vm: NotesViewModel) -> some View {
        HStack {
            Text("Notes")
                .panelHeaderStyle()
            Spacer()
            HStack(spacing: AppUI.Spacing.xxl) {
                browseToggle(.list, icon: "checklist.unchecked")
                browseToggle(.graph, icon: "point.3.connected.trianglepath.dotted")
            }
            if vm.notesBrowseMode == .list {
                Spacer().frame(width: AppUI.Spacing.xxl)
                Button { commandRouter.pendingCommand = .createNote } label: {
                    Image(systemName: "plus")
                        .font(AppUI.Font.label)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Note")
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    private func browseToggle(
        _ mode: NotesViewModel.NotesBrowseMode, icon: String
    ) -> some View {
        let isActive = notesViewModel.notesBrowseMode == mode
        return Button { notesViewModel.notesBrowseMode = mode } label: {
            Image(systemName: isActive ? icon + ".fill" : icon)
                .font(AppUI.Font.label)
                .foregroundColor(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .help(mode == .list ? "List" : "Graph")
    }

    func notesList(vm: NotesViewModel) -> some View {
        let composerActive = commandRouter.isComposerNotesActive
        let isNoteSplit = commandRouter.isNoteDualPaneActive
        let splitIDs = activeContentTab?.splitNoteIDs
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: AppUI.Spacing.sm) {
                ForEach(vm.filteredNotes) { note in
                    let inCurrentTab = activeContentTab?.containsNote(note.id) ?? false
                    let isFocused = vm.selectedNoteID == note.id
                    let activeState = inCurrentTab && isFocused
                    let splitState = inCurrentTab && !isFocused && isNoteSplit
                    SidebarNoteRow(
                        note: note,
                        isActive: activeState,
                        isInSplit: splitState,
                        composerActive: composerActive,
                        onOpen: {
                            if isNoteSplit, let ids = splitIDs {
                                // Clicking a note already in the split shifts focus.
                                if note.id == ids.left {
                                    commandRouter.focusDualPane(.left)
                                } else if note.id == ids.right {
                                    commandRouter.focusDualPane(.right)
                                } else {
                                    onOpenNote?(note.id, note.title)
                                }
                            } else {
                                onOpenNote?(note.id, note.title)
                            }
                        },
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
    /// True when the note is in the active split tab but in the non-focused pane.
    var isInSplit: Bool = false
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
                        .foregroundColor(isActive || isInSplit ? .primary : .secondary)
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
                if !note.tags.isEmpty {
                    Text(note.tags.joined(separator: " · "))
                        .font(AppUI.Font.micro)
                        .foregroundColor(.brandGreen.opacity(0.7))
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
                .stroke(
                    isActive ? Color.brandGreen.opacity(AppUI.Opacity.border)
                        : isInSplit ? Color.brandGreen.opacity(AppUI.Opacity.border * 0.6)
                        : .clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { rowTapped() }
        .onHover { isHovered = $0 }
        .draggable(note.body)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.title.isEmpty ? "Untitled Note" : note.title)
        .accessibilityValue(notePreview(note.body) ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAction(.default) { rowTapped() }
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
            .fill(
                isActive ? Color.brandGreen.opacity(AppUI.Opacity.selected)
                    : isInSplit ? Color.brandGreen.opacity(AppUI.Opacity.selected * 0.4)
                    : .clear
            )
    }

    private var insertButton: some View {
        Button {
            onInsert(note.body)
        } label: {
            Image(systemName: "arrow.right.circle.fill")
                .font(AppUI.Font.title2Regular)
                .foregroundColor(.brandGreen)
        }
        .buttonStyle(.plain)
        .help("Insert into Composer")
        .transition(.opacity)
    }

    private var favoriteIcon: some View {
        Button { onToggleFavorite() } label: {
            Image(systemName: note.isFavorite ? "star.fill" : "star")
                .font(AppUI.Font.label)
                .foregroundColor(note.isFavorite ? .brandGreen : .secondary)
        }
        .buttonStyle(.plain)
        .help(note.isFavorite ? "Remove from favorites" : "Add to favorites")
        .accessibilityLabel(note.isFavorite ? "Remove from favorites" : "Add to favorites")
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
