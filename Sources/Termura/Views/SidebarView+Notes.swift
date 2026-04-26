import SwiftUI

// MARK: - Notes Tab

//
// `SidebarNoteRow` (the row view) lives in `SidebarNoteRow.swift`.

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
