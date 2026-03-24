import SwiftUI

// MARK: - Search Tab

extension SidebarView {
    @ViewBuilder
    var searchContent: some View {
        if let service = searchService {
            SidebarSearchContent(
                searchService: service,
                onSelectSession: { id in sessionStore.activateSession(id: id) }
            )
        } else {
            sidebarEmptyState(icon: "magnifyingglass", message: "Search unavailable")
        }
    }
}

/// Search content following the Agent tab structure: header → divider → content.
struct SidebarSearchContent: View {
    @StateObject private var viewModel: SearchViewModel
    let onSelectSession: (SessionID) -> Void

    init(searchService: SearchService, onSelectSession: @escaping (SessionID) -> Void) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(searchService: searchService))
        self.onSelectSession = onSelectSession
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            resultsList
        }
    }

    private var header: some View {
        HStack {
            Text("Search")
                .panelHeaderStyle()
            Spacer()
            if viewModel.isSearching {
                ProgressView().scaleEffect(0.6)
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    private var searchField: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(AppUI.Font.caption)
            TextField("Search\u{2026}", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(AppUI.Font.body)
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.md)
    }

    @ViewBuilder
    private var resultsList: some View {
        let allResults: [SearchResult] = viewModel.results.sessions.map { .session($0) }
            + viewModel.results.notes.map { .note($0) }
        if allResults.isEmpty && !viewModel.query.isEmpty && !viewModel.isSearching {
            VStack(spacing: AppUI.Spacing.smMd) {
                Image(systemName: "magnifyingglass")
                    .font(AppUI.Font.hero)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
                Text("No results")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(allResults) { result in
                        SearchResultRowView(result: result)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if case let .session(s) = result {
                                    onSelectSession(s.id)
                                }
                            }
                    }
                }
                .padding(.horizontal, AppUI.Spacing.sm)
            }
        }
    }
}

// MARK: - Notes Tab

extension SidebarView {
    @ViewBuilder
    var notesContent: some View {
        if let vm = notesViewModel {
            VStack(spacing: 0) {
                notesHeader(vm: vm)
                notesList(vm: vm)
            }
            .task { await vm.loadNotes() }
        } else {
            sidebarEmptyState(icon: "doc.text", message: "Notes unavailable")
        }
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
            HStack {
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
            .overlay(
                Rectangle()
                    .stroke(isActive ? Color.accentColor.opacity(AppUI.Opacity.border) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
