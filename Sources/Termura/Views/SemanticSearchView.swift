import SwiftUI

/// Semantic search UI — queries across sessions and rule files using embeddings.
/// Shown alongside the existing FTS5 search as a "Semantic" tab.
struct SemanticSearchView: View {
    let vectorService: VectorSearchService
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
        .frame(width: 500, height: 400)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Semantic search\u{2026}", text: $query)
                .textFieldStyle(.plain)
                .font(DS.Font.searchField)
                .onSubmit { performSearch() }
            if isSearching {
                ProgressView().scaleEffect(0.7)
            }
            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding(DS.Spacing.lg)
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
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Image(systemName: hit.isRuleResult ? "doc.text" : "terminal")
                    .foregroundColor(hit.isRuleResult ? .orange : .blue)
                    .font(DS.Font.label)
                if let heading = hit.sectionHeading {
                    Text(heading).font(DS.Font.bodyMedium)
                } else {
                    Text("Session output").font(DS.Font.bodyMedium)
                }
                Spacer()
                Text(String(format: "%.0f%%", hit.score * 100))
                    .font(DS.Font.captionMono)
                    .foregroundColor(.secondary)
            }
            Text(hit.text.prefix(120) + (hit.text.count > 120 ? "\u{2026}" : ""))
                .font(DS.Font.label)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= AppConfig.Search.minQueryLength else { return }
        isSearching = true
        let service = vectorService
        Task {
            let hits = await service.search(query: q)
            await MainActor.run {
                results = hits
                isSearching = false
            }
        }
    }
}
