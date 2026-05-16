import SwiftUI

/// One entry in the Welcome window's recent-projects list. Hover
/// reveals an "x" that removes the project from the recents file (the
/// project on disk is untouched).
struct WelcomeRecentRow: View {
    let project: RecentProject
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: "folder.fill")
                .foregroundColor(.brandGreen)
                .frame(width: AppUI.Size.iconFrameLarge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
                Text(project.displayName)
                    .font(AppUI.Font.bodyMedium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(abbreviatedPath)
                    .font(AppUI.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from recents")
                .accessibilityLabel("Remove from recents")
            }
        }
        .padding(.horizontal, AppUI.Spacing.xl)
        .padding(.vertical, AppUI.Spacing.md)
        .contentShape(Rectangle())
        .background(rowBackground)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Click to open this project")
    }

    private var rowBackground: Color {
        isHovering ? Color.brandGreen.opacity(AppUI.Opacity.tint) : Color.clear
    }

    /// Replaces the user home with `~` for shorter, less identifying
    /// labels in the row. Falls back to the full path when the project
    /// lives outside `$HOME`.
    private var abbreviatedPath: String {
        let home = NSHomeDirectory()
        if project.path.hasPrefix(home + "/") {
            return "~" + project.path.dropFirst(home.count)
        }
        return project.path
    }
}
