import SwiftUI

// MARK: - Knowledge Tab

extension SidebarView {
    @ViewBuilder
    var knowledgeContent: some View {
        VStack(spacing: 0) {
            knowledgeHeader
            knowledgeBody
        }
        .task {
            if notesViewModel.notes.isEmpty { await notesViewModel.loadNotes() }
        }
    }

    private var knowledgeHeader: some View {
        HStack {
            Text("Knowledge")
                .panelHeaderStyle()
            Spacer()
            knowledgeBrowseModeMenu
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    private var knowledgeBrowseModeMenu: some View {
        Menu {
            ForEach(NotesViewModel.KnowledgeBrowseMode.allCases) { mode in
                Button {
                    notesViewModel.knowledgeBrowseMode = mode
                } label: {
                    if mode == notesViewModel.knowledgeBrowseMode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Text(mode.label)
                    }
                }
            }
        } label: {
            HStack(spacing: AppUI.Spacing.xs) {
                Text(notesViewModel.knowledgeBrowseMode.label)
                    .font(AppUI.Font.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var knowledgeBody: some View {
        switch notesViewModel.knowledgeBrowseMode {
        case .tags:
            knowledgeList { knowledgeTagGroups }
        case .timeline:
            knowledgeList { knowledgeTimelineGroups }
        case .graph:
            knowledgeGraphView
        case .sources:
            knowledgeList { knowledgeSourceGroups }
        case .log:
            knowledgeList { knowledgeLogGroups }
        }
    }

    private func knowledgeList(@ViewBuilder content: () -> some View) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: AppUI.Spacing.md) {
                content()
            }
            .padding(.horizontal, AppUI.Spacing.lg)
        }
    }

    private var knowledgeGraphView: some View {
        KnowledgeGraphView(
            theme: themeManager.current,
            graphJSON: notesViewModel.knowledgeGraphJSON,
            onOpenNote: { title in
                guard let note = notesViewModel.findNote(byTitle: title) else { return }
                navigateToNote(id: note.id, title: note.title)
            },
            onFilterTag: { tag in
                notesViewModel.selectedTagFilter = tag
                commandRouter.selectedSidebarTab = .notes
            }
        )
    }

    // MARK: - Tag Groups

    @ViewBuilder
    private var knowledgeTagGroups: some View {
        let groups = notesViewModel.notesByTag
        if groups.isEmpty {
            knowledgeEmptyState(message: "No tagged notes yet.")
        } else {
            ForEach(groups, id: \.tag) { group in
                KnowledgeGroupSection(
                    title: group.tag,
                    notes: group.notes,
                    onOpenNote: { id, title in navigateToNote(id: id, title: title) }
                )
            }
        }
    }

    // MARK: - Timeline Groups

    @ViewBuilder
    private var knowledgeTimelineGroups: some View {
        let groups = notesViewModel.notesByTimePeriod
        if groups.isEmpty {
            knowledgeEmptyState(message: "No notes yet.")
        } else {
            ForEach(groups, id: \.period) { group in
                KnowledgeGroupSection(
                    title: group.period,
                    notes: group.notes,
                    onOpenNote: { id, title in navigateToNote(id: id, title: title) }
                )
            }
        }
    }

    // MARK: - Sources Groups

    @ViewBuilder
    private var knowledgeSourceGroups: some View {
        let entries = notesViewModel.sourceEntries
        if entries.isEmpty {
            knowledgeEmptyState(message: "No source files yet.")
        } else {
            let grouped = Dictionary(grouping: entries, by: \.category)
            ForEach(grouped.keys.sorted(), id: \.self) { category in
                KnowledgeGroupSection(
                    title: category,
                    files: grouped[category] ?? [],
                    onOpenFile: { entry in openKnowledgeFile(entry, prefix: "sources") }
                )
            }
        }
    }

    // MARK: - Log Groups

    @ViewBuilder
    private var knowledgeLogGroups: some View {
        let entries = notesViewModel.logEntries
        if entries.isEmpty {
            knowledgeEmptyState(message: "No session logs yet.")
        } else {
            let grouped = Dictionary(grouping: entries, by: \.category)
            ForEach(grouped.keys.sorted().reversed(), id: \.self) { category in
                KnowledgeGroupSection(
                    title: category,
                    files: grouped[category] ?? [],
                    onOpenFile: { entry in openKnowledgeFile(entry, prefix: "log") }
                )
            }
        }
    }

    // MARK: - Helpers

    private func knowledgeEmptyState(message: String) -> some View {
        Text(message)
            .font(AppUI.Font.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, AppUI.Spacing.xxxxl)
    }

    private func navigateToNote(id: NoteID, title: String) {
        commandRouter.selectedSidebarTab = .notes
        onOpenNote?(id, title)
    }

    private func openKnowledgeFile(_ entry: KnowledgeFileEntry, prefix: String) {
        guard !entry.isDirectory, let dir = notesViewModel.notesDirectoryURL else { return }
        let knowledgeRoot = dir.deletingLastPathComponent()
        let fullPath = knowledgeRoot
            .appendingPathComponent(prefix)
            .appendingPathComponent(entry.relativePath).path
        onOpenFile?(fullPath, .preview)
    }
}
