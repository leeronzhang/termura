import SwiftUI

/// Row for a file entry in the Sources or Log browser.
struct KnowledgeFileRow: View {
    let entry: KnowledgeFileEntry
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppUI.Spacing.md) {
                Image(systemName: iconName)
                    .font(AppUI.Font.caption)
                    .foregroundColor(iconColor)
                    .frame(width: 14)
                Text(entry.name)
                    .font(AppUI.Font.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                if let date = entry.modifiedAt {
                    Text(shortDate(date))
                        .font(AppUI.Font.micro)
                        .foregroundColor(.secondary)
                }
                if let size = entry.fileSize {
                    Text(formattedSize(size))
                        .font(AppUI.Font.micro)
                        .foregroundColor(.secondary)
                }
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

    private var iconName: String {
        if entry.isDirectory { return "folder" }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "txt", "log": return "doc.text"
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        case "json", "csv": return "tablecells"
        case "swift", "py", "js", "ts", "sh": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        if entry.isDirectory { return .brandGreen }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "txt", "log": return .secondary
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return .purple
        default: return .secondary
        }
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

    private func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}
