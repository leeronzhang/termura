import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @Binding var isPresented: Bool
    let onSelectSession: (SessionID) -> Void
    let vectorService: VectorSearchService?

    @State private var searchMode: SearchMode = .keyword

    init(
        searchService: SearchService,
        isPresented: Binding<Bool>,
        onSelectSession: @escaping (SessionID) -> Void,
        vectorService: VectorSearchService? = nil
    ) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(searchService: searchService))
        _isPresented = isPresented
        self.onSelectSession = onSelectSession
        self.vectorService = vectorService
    }

    var body: some View {
        VStack(spacing: 0) {
            if vectorService != nil {
                searchModePicker
            }
            if searchMode == .keyword {
                searchField
                Divider()
                resultsList
            } else if let vs = vectorService {
                SemanticSearchView(
                    vectorService: vs,
                    onSelectSession: onSelectSession,
                    isPresented: $isPresented
                )
            }
        }
        .frame(width: 500, height: 400)
    }

    private var searchModePicker: some View {
        Picker("", selection: $searchMode) {
            Text("Keyword").tag(SearchMode.keyword)
            Text("Semantic").tag(SearchMode.semantic)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .padding(DS.Spacing.md)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .frame(width: DS.Size.iconFrame)
            TextField("Search sessions and notes\u{2026}", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(DS.Font.searchField)
            if viewModel.isSearching {
                ProgressView().scaleEffect(0.7)
            }
            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(DS.Font.label)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.mdLg)
    }

    // MARK: - Results list

    @ViewBuilder
    private var resultsList: some View {
        let allResults: [SearchResult] = viewModel.results.sessions.map { .session($0) }
            + viewModel.results.notes.map { .note($0) }
        if allResults.isEmpty && !viewModel.query.isEmpty && !viewModel.isSearching {
            Text("No results for \u{201C}\(viewModel.query)\u{201D}")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(allResults) { result in
                SearchResultRowView(result: result)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if case .session(let s) = result {
                            onSelectSession(s.id)
                            isPresented = false
                        }
                    }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Search Mode

private enum SearchMode: String, CaseIterable {
    case keyword
    case semantic
}
