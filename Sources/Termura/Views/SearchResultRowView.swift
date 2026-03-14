import SwiftUI

enum SearchResult: Identifiable {
    case session(SessionRecord)
    case note(NoteRecord)

    var id: String {
        switch self {
        case .session(let s): return "session-\(s.id.rawValue)"
        case .note(let n): return "note-\(n.id.rawValue)"
        }
    }
}

struct SearchResultRowView: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .frame(width: 16)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch result {
        case .session: return "terminal"
        case .note: return "note.text"
        }
    }

    private var title: String {
        switch result {
        case .session(let s): return s.title
        case .note(let n): return n.title.isEmpty ? "Untitled Note" : n.title
        }
    }

    private var subtitle: String {
        switch result {
        case .session(let s):
            return s.workingDirectory.isEmpty ? "No directory" : s.workingDirectory
        case .note(let n):
            let preview = n.body.prefix(AppConfig.Search.snippetLength)
            return preview.isEmpty ? "Empty note" : String(preview)
        }
    }
}
