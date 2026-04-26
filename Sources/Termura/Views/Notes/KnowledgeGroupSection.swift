import SwiftUI

/// Collapsible section for Knowledge tab: header with title + count, expandable rows.
/// Supports both note rows and file entry rows via separate initializers.
struct KnowledgeGroupSection: View {
    let title: String
    let itemCount: Int
    let content: AnyView
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            sectionHeader
            if isExpanded {
                VStack(spacing: AppUI.Spacing.xxs) {
                    content
                }
                .padding(.leading, AppUI.Spacing.lg)
            }
        }
    }

    private var sectionHeader: some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } } label: {
            HStack(spacing: AppUI.Spacing.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(AppUI.Font.micro)
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Text(title)
                    .font(AppUI.Font.labelMedium)
                    .foregroundColor(.primary)
                Text("\(itemCount)")
                    .font(AppUI.Font.micro)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, AppUI.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note rows

    init(title: String, notes: [NoteRecord], onOpenNote: @escaping (NoteID, String) -> Void) {
        self.title = title
        itemCount = notes.count
        content = AnyView(ForEach(notes) { note in
            KnowledgeNoteRow(note: note, onOpen: { onOpenNote(note.id, note.title) })
        })
    }

    // MARK: - File entry rows

    init(title: String, files: [KnowledgeFileEntry], onOpenFile: @escaping (KnowledgeFileEntry) -> Void) {
        self.title = title
        itemCount = files.count
        content = AnyView(ForEach(files) { entry in
            KnowledgeFileRow(entry: entry, onOpen: { onOpenFile(entry) })
        })
    }
}

/// Simplified note row for Knowledge tab: title + date only.
private struct KnowledgeNoteRow: View {
    let note: NoteRecord
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(AppUI.Font.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text(shortDate(note.updatedAt))
                    .font(AppUI.Font.micro)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, AppUI.Spacing.xxs)
            .padding(.horizontal, AppUI.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppUI.Radius.sm)
                    .fill(isHovered ? Color.secondary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func shortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
