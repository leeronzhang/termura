import SwiftUI

/// Snippets tab content for the Composer overlay.
struct ComposerSnippetsView: View {
    @ObservedObject var editorViewModel: EditorViewModel
    var notesViewModel: NotesViewModel
    @Binding var snippetSearch: String
    let onSwitchToCompose: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().padding(.horizontal, AppUI.Spacing.xxl)
            snippetList
        }
    }

    private var searchBar: some View {
        HStack(spacing: AppUI.Spacing.smMd) {
            Image(systemName: "magnifyingglass")
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary)
            TextField("Search snippets", text: $snippetSearch)
                .textFieldStyle(.plain)
                .font(AppUI.Font.body)
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.vertical, AppUI.Spacing.md)
    }

    private var snippetList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if filteredSnippets.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: AppUI.Spacing.xxs) {
                    ForEach(filteredSnippets) { snippet in
                        snippetRow(snippet)
                    }
                }
                .padding(.horizontal, AppUI.Spacing.lgXl)
                .padding(.vertical, AppUI.Spacing.md)
            }
        }
    }

    private var filteredSnippets: [NoteRecord] {
        if snippetSearch.isEmpty { return notesViewModel.snippets }
        let query = snippetSearch.lowercased()
        return notesViewModel.snippets.filter {
            $0.title.lowercased().contains(query) || $0.body.lowercased().contains(query)
        }
    }

    private func snippetRow(_ snippet: NoteRecord) -> some View {
        HStack(spacing: AppUI.Spacing.md) {
            Button {
                editorViewModel.updateText(snippet.body)
                onSwitchToCompose()
            } label: {
                VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
                    Text(snippet.title.isEmpty ? snippetPreview(snippet.body) : snippet.title)
                        .font(AppUI.Font.labelMedium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(snippetPreview(snippet.body))
                        .font(AppUI.Font.captionMono)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                editorViewModel.updateText(snippet.body)
                editorViewModel.submit()
                onDismiss()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(AppUI.Font.caption)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Send to terminal")

            Button {
                notesViewModel.deleteSnippet(id: snippet.id)
            } label: {
                Image(systemName: "trash")
                    .font(AppUI.Font.caption)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
            }
            .buttonStyle(.plain)
            .help("Delete snippet")
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.smMd)
        .background(Color.secondary.opacity(AppUI.Opacity.whisper))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var emptyState: some View {
        VStack(spacing: AppUI.Spacing.md) {
            Image(systemName: "text.snippet")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
            Text("No snippets yet")
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
            Text("Save commands from the Compose tab")
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppUI.Spacing.xxxxl)
    }

    private func snippetPreview(_ body: String) -> String {
        let line = body.components(separatedBy: .newlines).first ?? body
        let limit = AppConfig.Search.snippetLength
        return line.count > limit ? String(line.prefix(limit)) + "..." : line
    }
}
