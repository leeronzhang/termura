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
            return s.workingDirectory.isEmpty ? "No directory" : s.workingDirectory
        case let .note(n):
            let preview = n.body.prefix(AppConfig.Search.previewLength)
            return preview.isEmpty ? "Empty note" : String(preview)
        }
    }
}
