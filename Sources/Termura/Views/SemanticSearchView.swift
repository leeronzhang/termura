import SwiftUI

#if DEBUG

/// Semantic search UI — queries across sessions and rule files using embeddings.
/// Shown alongside the existing FTS5 search as a "Semantic" tab.
///
/// DEBUG-ONLY: Backed by FNV hash vectors with no real semantic content.
/// Do not enable in production until `EmbeddingService` uses a real Core ML model.
struct SemanticSearchView: View {
    let vectorService: any VectorSearchServiceProtocol
    let onSelectSession: (SessionID) -> Void
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .frame(width: AppConfig.UI.searchDialogWidth, height: AppConfig.UI.searchDialogHeight)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Semantic search\u{2026}", text: $query)
                .textFieldStyle(.plain)
                .font(AppUI.Font.searchField)
                .onSubmit { performSearch() }
            if isSearching {
                ProgressView().scaleEffect(AppConfig.UI.progressIndicatorScale)
            }
            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding(AppUI.Spacing.lg)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty && !query.isEmpty && !isSearching {
            Text("No semantic matches for \u{201C}\(query)\u{201D}")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(results) { hit in
                hitRow(hit)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let sid = hit.sessionID {
                            onSelectSession(sid)
                            isPresented = false
                        }
                    }
            }
            .listStyle(.plain)
        }
    }

    private func hitRow(_ hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            HStack {
                Image(systemName: hit.isRuleResult ? "doc.text" : "terminal")
                    .foregroundColor(hit.isRuleResult ? .orange : .blue)
                    .font(AppUI.Font.label)
                if let heading = hit.sectionHeading {
                    Text(heading).font(AppUI.Font.bodyMedium)
                } else {
                    Text("Session output").font(AppUI.Font.bodyMedium)
                }
                Spacer()
                Text(String(format: "%.0f%%", hit.score * 100))
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary)
            }
            Text(hit.text.prefix(120) + (hit.text.count > 120 ? "\u{2026}" : ""))
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, AppUI.Spacing.sm)
    }

    private func performSearch() {
        let queryText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard queryText.count >= AppConfig.Search.minQueryLength else { return }
        isSearching = true
        let service = vectorService
        Task {
            let hits = await service.search(query: queryText, topK: AppConfig.SemanticSearch.topK)
            await MainActor.run {
                results = hits
                isSearching = false
            }
        }
    }
}

#endif
