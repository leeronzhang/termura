import SwiftUI

/// Identifies an open tab in the main content area.
/// Terminal tabs carry a SessionID so each session gets its own tab.
enum ContentTab: Identifiable, Hashable, Codable {
    case terminal(SessionID, String) // sessionID, session title
    case note(NoteID, String)
    case diff(String, Bool, Bool) // file path, isStaged, isUntracked
    case file(String, String) // relativePath, fileName
    case preview(String, String) // relativePath, fileName (read-only QuickLook)

    var id: String {
        switch self {
        case .terminal(let sid, _): return "terminal-\(sid)"
        case .note(let noteID, _): return "note-\(noteID)"
        case .diff(let path, let staged, _): return "diff-\(staged ? "staged" : "wt")-\(path)"
        case .file(let path, _): return "file-\(path)"
        case .preview(let path, _): return "preview-\(path)"
        }
    }

    var title: String {
        switch self {
        case .terminal(_, let name): return name.isEmpty ? "Terminal" : name
        case .note(_, let name): return name.isEmpty ? "Untitled" : name
        case .diff(let path, _, _): return URL(fileURLWithPath: path).lastPathComponent
        case .file(_, let name): return name
        case .preview(_, let name): return name
        }
    }

    var icon: String {
        switch self {
        case .terminal: return "terminal"
        case .note: return "doc.text"
        case .diff: return "doc.text.magnifyingglass"
        case .file: return "doc.text"
        case .preview: return "eye"
        }
    }

    /// Terminal tabs are managed via the sidebar — not closable from the tab bar.
    var isClosable: Bool {
        switch self {
        case .terminal: return false
        case .note, .diff, .file, .preview: return true
        }
    }

    /// Whether this tab represents a terminal session.
    var isTerminal: Bool {
        if case .terminal = self { return true }
        return false
    }

    /// The session ID if this is a terminal tab.
    var sessionID: SessionID? {
        if case .terminal(let sid, _) = self { return sid }
        return nil
    }

    /// The file path if this is a file, preview, or diff tab.
    var filePath: String? {
        switch self {
        case .file(let path, _), .preview(let path, _), .diff(let path, _, _):
            return path
        case .terminal, .note:
            return nil
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
