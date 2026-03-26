import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @Binding var isPresented: Bool
    let onSelectSession: (SessionID) -> Void
    let vectorService: (any VectorSearchServiceProtocol)?

    @State private var searchMode: SearchMode = .keyword

    init(
        searchService: any SearchServiceProtocol,
        isPresented: Binding<Bool>,
        onSelectSession: @escaping (SessionID) -> Void,
        vectorService: (any VectorSearchServiceProtocol)? = nil
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
        .frame(width: AppConfig.UI.searchDialogWidth, height: AppConfig.UI.searchDialogHeight)
    }

    private var searchModePicker: some View {
        Picker("", selection: $searchMode) {
            Text("Keyword").tag(SearchMode.keyword)
            Text("Semantic").tag(SearchMode.semantic)
        }
        .pickerStyle(.segmented)
        .frame(width: AppConfig.UI.fieldPickerWidth)
        .padding(AppUI.Spacing.md)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .frame(width: AppUI.Size.iconFrame)
            TextField("Search sessions and notes\u{2026}", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(AppUI.Font.searchField)
            if viewModel.isSearching {
                ProgressView().scaleEffect(0.7)
            }
            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(AppUI.Font.label)
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.mdLg)
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
                        if case let .session(s) = result {
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
