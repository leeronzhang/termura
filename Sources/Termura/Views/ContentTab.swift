import SwiftUI

/// Identifies an open tab in the main content area.
/// Terminal tabs carry a SessionID so each session gets its own tab.
enum ContentTab: Identifiable, Hashable, Codable {
    case terminal(sessionID: SessionID, title: String)
    case note(noteID: NoteID, title: String)
    case diff(path: String, isStaged: Bool, isUntracked: Bool)
    case file(path: String, name: String)
    case preview(path: String, name: String)

    var id: String {
        switch self {
        case let .terminal(sessionID, _): "terminal-\(sessionID)"
        case let .note(noteID, _): "note-\(noteID)"
        case let .diff(path, isStaged, _): "diff-\(isStaged ? "staged" : "wt")-\(path)"
        case let .file(path, _): "file-\(path)"
        case let .preview(path, _): "preview-\(path)"
        }
    }

    var title: String {
        switch self {
        case let .terminal(_, title): title.isEmpty ? "Terminal" : title
        case let .note(_, title): title.isEmpty ? "Untitled" : title
        case let .diff(path, _, _): URL(fileURLWithPath: path).lastPathComponent
        case let .file(_, name): name
        case let .preview(_, name): name
        }
    }

    var icon: String {
        switch self {
        case .terminal: "terminal"
        case .note: "doc.text"
        case .diff: "doc.text.magnifyingglass"
        case .file: "doc.text"
        case .preview: "eye"
        }
    }

    /// Terminal tabs are managed via the sidebar — not closable from the tab bar.
    var isClosable: Bool {
        switch self {
        case .terminal: false
        case .note, .diff, .file, .preview: true
        }
    }

    /// Whether this tab represents a terminal session.
    var isTerminal: Bool {
        if case .terminal = self { return true }
        return false
    }

    /// The session ID if this is a terminal tab.
    var sessionID: SessionID? {
        if case let .terminal(sessionID, _) = self { return sessionID }
        return nil
    }

    /// The file path if this is a file, preview, or diff tab.
    var filePath: String? {
        switch self {
        case let .file(path, _), let .preview(path, _), let .diff(path, _, _):
            path
        case .terminal, .note:
            nil
        }
    }
}

/// Horizontal tab strip for the main content area.
struct ContentTabBar: View {
    let tabs: [ContentTab]
    @Binding var selectedTab: ContentTab
    var isFullScreen: Bool = false
    let onClose: (ContentTab) -> Void

    /// Extra top space so the tab content aligns with the sidebar icons,
    /// sitting just below the traffic-light buttons in non-fullscreen.
    private var titleBarTop: CGFloat { isFullScreen ? 0 : AppUI.Spacing.smMd }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.top, titleBarTop)
        .frame(height: AppConfig.UI.contentTabBarHeight + titleBarTop)
        .background(Color.black.opacity(AppUI.Opacity.tabBar))
    }

    private func tabButton(_ tab: ContentTab) -> some View {
        let isSelected = selectedTab == tab
        return HStack(spacing: AppUI.Spacing.sm) {
            Image(systemName: tab.icon)
                .font(AppUI.Font.caption)
            Text(tab.title)
                .font(AppUI.Font.label)
                .lineLimit(1)
            Spacer()
            if tab.isClosable {
                Image(systemName: "xmark")
                    .font(AppUI.Font.micro)
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle().size(width: 24, height: 24))
                    .onTapGesture { onClose(tab) }
            }
        }
        .foregroundColor(isSelected ? .primary : .secondary)
        .padding(.horizontal, 18)
        .frame(maxWidth: 200, maxHeight: .infinity)
        .background(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = tab }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
