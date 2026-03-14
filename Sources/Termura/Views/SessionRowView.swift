import SwiftUI

/// A single row in the session sidebar.
struct SessionRowView: View {
    let session: SessionRecord
    let isActive: Bool
    let hasUnreadFailure: Bool
    let onActivate: () -> Void
    let onRename: (String) -> Void
    let onClose: () -> Void

    @State private var isEditing = false
    @State private var editTitle = ""
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 8) {
            colorDot
            sessionTitle
            Spacer()
            if hasUnreadFailure {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            }
            closeButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(rowBackground)
        .cornerRadius(6)
        .onTapGesture(count: 2) { beginEditing() }
        .onTapGesture(count: 1) { onActivate() }
        .contextMenu { contextMenuItems }
    }

    // MARK: - Subviews

    private var colorDot: some View {
        Circle()
            .fill(colorForLabel(session.colorLabel))
            .frame(width: 8, height: 8)
            .opacity(session.colorLabel == .none ? 0 : 1)
    }

    @ViewBuilder
    private var sessionTitle: some View {
        if isEditing {
            TextField("Session name", text: $editTitle, onCommit: commitEdit)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(themeManager.current.sidebarText)
                .onExitCommand { cancelEdit() }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.current.sidebarText)
                    .lineLimit(1)
                if let dir = workingDirectorySubtitle {
                    Text(dir)
                        .font(.system(size: 10))
                        .foregroundColor(themeManager.current.sidebarText.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
    }

    private var workingDirectorySubtitle: String? {
        let path = session.workingDirectory
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(themeManager.current.sidebarText.opacity(0.5))
        }
        .buttonStyle(.plain)
        .opacity(isActive ? 1 : 0)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                isActive
                    ? themeManager.current.activeSessionHighlight.opacity(0.3)
                    : Color.clear
            )
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Rename") { beginEditing() }
        Divider()
        Button("Close Session", role: .destructive) { onClose() }
    }

    // MARK: - Edit helpers

    private func beginEditing() {
        editTitle = session.title
        isEditing = true
    }

    private func commitEdit() {
        isEditing = false
        let trimmed = editTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onRename(trimmed)
    }

    private func cancelEdit() {
        isEditing = false
    }

    private func colorForLabel(_ label: SessionColorLabel) -> Color {
        switch label {
        case .none: .clear
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}
