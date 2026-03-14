import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @Binding var isPresented: Bool
    let onSelectSession: (SessionID) -> Void

    init(
        searchService: SearchService,
        isPresented: Binding<Bool>,
        onSelectSession: @escaping (SessionID) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(searchService: searchService))
        _isPresented = isPresented
        self.onSelectSession = onSelectSession
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search sessions and notes\u{2026}", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
            if viewModel.isSearching {
                ProgressView().scaleEffect(0.7)
            }
            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding(12)
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
