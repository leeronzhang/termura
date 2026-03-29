import SwiftUI

/// Identifies an open tab in the main content area.
/// Terminal tabs carry a SessionID; split tabs carry two session IDs.
enum ContentTab: Identifiable, Hashable, Codable {
    case terminal(sessionID: SessionID, title: String)
    case split(left: SessionID, right: SessionID, leftTitle: String, rightTitle: String)
    case note(noteID: NoteID, title: String)
    case diff(path: String, isStaged: Bool, isUntracked: Bool)
    case file(path: String, name: String)
    case preview(path: String, name: String)

    var id: String {
        switch self {
        case let .terminal(sessionID, _): "terminal-\(sessionID)"
        case let .split(left, right, _, _): "split-\(left)-\(right)"
        case let .note(noteID, _): "note-\(noteID)"
        case let .diff(path, isStaged, _): "diff-\(isStaged ? "staged" : "wt")-\(path)"
        case let .file(path, _): "file-\(path)"
        case let .preview(path, _): "preview-\(path)"
        }
    }

    var title: String {
        switch self {
        case let .terminal(_, title): title.isEmpty ? "Terminal" : title
        case let .split(_, _, leftTitle, rightTitle):
            "\(leftTitle.isEmpty ? "Terminal" : leftTitle) | \(rightTitle.isEmpty ? "Terminal" : rightTitle)"
        case let .note(_, title): title.isEmpty ? "Untitled" : title
        case let .diff(path, _, _): URL(fileURLWithPath: path).lastPathComponent
        case let .file(_, name): name
        case let .preview(_, name): name
        }
    }

    var icon: String {
        switch self {
        case .terminal: "terminal"
        case .split: "rectangle.split.2x1"
        case .note: "doc.text"
        case .diff: "doc.text.magnifyingglass"
        case .file: "doc.text"
        case .preview: "eye"
        }
    }

    /// Filename to resolve via FileTypeIcon for asset-based icons.
    /// Returns nil for terminal/split tabs which use SF Symbols.
    var fileTypeIconName: String? {
        switch self {
        case .terminal, .split: return nil
        case .note: return "readme.md"
        case let .diff(path, _, _): return URL(fileURLWithPath: path).lastPathComponent
        case let .file(_, name): return name
        case let .preview(_, name): return name
        }
    }

    /// Split and terminal tabs are managed via the sidebar — not closable from the tab bar.
    var isClosable: Bool {
        switch self {
        case .terminal, .split: false
        case .note, .diff, .file, .preview: true
        }
    }

    /// Whether this tab represents a single terminal session.
    var isTerminal: Bool {
        if case .terminal = self { return true }
        return false
    }

    /// Whether this tab is a split pair of two terminal sessions.
    var isSplit: Bool {
        if case .split = self { return true }
        return false
    }

    /// Whether this tab is a Markdown note editor.
    var isNote: Bool {
        if case .note = self { return true }
        return false
    }

    /// The session ID if this is a single terminal tab.
    var sessionID: SessionID? {
        if case let .terminal(sessionID, _) = self { return sessionID }
        return nil
    }

    /// The left and right session IDs if this is a split tab.
    var splitSessionIDs: (left: SessionID, right: SessionID)? {
        if case let .split(left, right, _, _) = self { return (left, right) }
        return nil
    }

    /// Whether either slot of this tab contains the given session.
    func containsSession(_ id: SessionID) -> Bool {
        switch self {
        case let .terminal(sid, _): return sid == id
        case let .split(left, right, _, _): return left == id || right == id
        case .note, .diff, .file, .preview: return false
        }
    }

    /// The file path if this is a file, preview, or diff tab.
    var filePath: String? {
        switch self {
        case let .file(path, _), let .preview(path, _), let .diff(path, _, _):
            path
        case .terminal, .split, .note:
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

    @ViewBuilder
    private func tabIcon(for tab: ContentTab) -> some View {
        if let name = tab.fileTypeIconName {
            FileTypeIcon.image(for: name)
                .resizable()
                .scaledToFit()
                .frame(width: AppUI.Size.fileTypeIcon, height: AppUI.Size.fileTypeIcon)
        } else {
            Image(systemName: tab.icon)
                .font(AppUI.Font.caption)
        }
    }

    private func tabButton(_ tab: ContentTab) -> some View {
        let isSelected = selectedTab == tab
        return HStack(spacing: AppUI.Spacing.sm) {
            tabIcon(for: tab)
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
