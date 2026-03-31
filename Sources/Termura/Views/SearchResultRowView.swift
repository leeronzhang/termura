import SwiftUI

enum SearchResult: Identifiable {
    case session(SessionRecord)
    case note(NoteRecord)

    var id: String {
        switch self {
        case let .session(s): "session-\(s.id.rawValue)"
        case let .note(n): "note-\(n.id.rawValue)"
        }
    }
}

struct SearchResultRowView: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: AppUI.Spacing.lg) {
            Image(systemName: iconName)
                .frame(width: AppUI.Size.iconFrame)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                Text(title)
                    .font(AppUI.Font.title3)
                    .lineLimit(1)
                Text(subtitle)
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, AppUI.Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resultTypeLabel + title)
        .accessibilityValue(subtitle)
    }

    private var resultTypeLabel: String {
        switch result {
        case .session: "Session: "
        case .note: "Note: "
        }
    }

    private var iconName: String {
        switch result {
        case .session: "terminal"
        case .note: "note.text"
        }
    }

    private var title: String {
        switch result {
        case let .session(s): s.title
        case let .note(n): n.title.isEmpty ? "Untitled Note" : n.title
        }
    }

    private var subtitle: String {
        switch result {
        case let .session(s):
            return s.workingDirectory ?? "No directory"
        case let .note(n):
            let preview = n.body.prefix(AppConfig.Search.previewLength)
            return preview.isEmpty ? "Empty note" : String(preview)
        }
    }
}

#if DEBUG
#Preview("Search Result Rows") {
    List {
        SearchResultRowView(result: .session(
            SessionRecord(title: "feat: SwiftUI previews", workingDirectory: "~/termura")
        ))
        SearchResultRowView(result: .session(
            SessionRecord(title: "Terminal Session")
        ))
        SearchResultRowView(result: .note(
            NoteRecord(title: "Architecture Notes", body: "The app uses a clean architecture pattern with ViewModels and Services...")
        ))
        SearchResultRowView(result: .note(
            NoteRecord(title: "", body: "")
        ))
    }
    .frame(width: 360, height: 200)
}
#endif
