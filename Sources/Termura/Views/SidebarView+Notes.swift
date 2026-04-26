import SwiftUI

// MARK: - Notes Tab

//
// `SidebarNoteRow` (the row view) lives in `SidebarNoteRow.swift`.

extension SidebarView {
    @ViewBuilder
    var notesContent: some View {
        VStack(spacing: 0) {
            notesHeader(vm: notesViewModel)
            if !notesViewModel.allTags.isEmpty {
                TagChipsBar(
                    tags: notesViewModel.allTags,
                    selectedTag: notesViewModel.selectedTagFilter,
                    onSelect: { notesViewModel.selectedTagFilter = $0 }
                )
            }
            notesList(vm: notesViewModel)
        }
        .task { await notesViewModel.loadNotes() }
    }

    func notesHeader(vm _: NotesViewModel) -> some View {
        HStack {
            Text("Notes")
                .panelHeaderStyle()
            Spacer()
            Button { commandRouter.pendingCommand = .createNote } label: {
                Image(systemName: "plus")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Note")
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
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
