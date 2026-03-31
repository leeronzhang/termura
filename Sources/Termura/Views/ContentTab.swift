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

    /// Whether the tab shows a close (xmark) button in the tab bar.
    /// Closing a terminal tab ends the session (PTY terminated, record preserved).
    /// Closing a split tab ends the focused pane session.
    var isClosable: Bool {
        switch self {
        case .terminal, .split: true
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
    @Binding var selectedTab: ContentTab?
    var isFullScreen: Bool = false
    /// When true, renders a sidebar reveal button at the leading edge (sidebar is hidden).
    var showSidebarButton: Bool = false
    var onShowSidebar: (() -> Void)?
    let onClose: (ContentTab) -> Void
    /// Mirrors the project-tab badge: blue dot when there are uncommitted changes.
    var hasUncommittedChanges: Bool = false
    /// Mirrors the project-tab badge: red dot (takes priority) when there are diagnostic errors.
    var diagnosticErrorCount: Int = 0

    /// Extra top space so the tab content aligns with the sidebar icons,
    /// sitting just below the traffic-light buttons in non-fullscreen.
    private var titleBarTop: CGFloat { isFullScreen ? 0 : AppUI.Spacing.smMd }
    private var tabsLeadingPadding: CGFloat {
        isFullScreen
            ? AppUI.Spacing.xxl + AppUI.Spacing.xxxxl
            : AppConfig.UI.trafficLightSafeLeading + AppUI.Spacing.xxxxl
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    tabButton(tab)
                }
                Spacer()
            }
            .padding(.top, titleBarTop)
            // Reserve space for the sidebar reveal button (safeLeading + button width)
            // so tab buttons do not slide under the toggle overlay.
            .padding(.leading, showSidebarButton ? tabsLeadingPadding : 0)

            if showSidebarButton {
                sidebarRevealButton
            }
        }
        .frame(height: AppConfig.UI.contentTabBarHeight + titleBarTop)
        .background(Color.black.opacity(AppUI.Opacity.tabBar))
    }

    private var sidebarRevealButton: some View {
        Button {
            onShowSidebar?()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "inset.filled.lefthalf.rectangle")
                    .font(AppUI.Font.tabBarIcon)
                    .foregroundColor(.secondary)

                if diagnosticErrorCount > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                        .offset(x: 3, y: -1)
                } else if hasUncommittedChanges {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                        .offset(x: 3, y: -1)
                }
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        // alignment: .leading so the icon's left edge sits exactly at the padding origin,
        // matching the leading edge of projectPathBar content (xxl = 20pt).
        // The extra frame width beyond the icon provides hit-area padding to the right.
        .frame(width: AppUI.Spacing.xxxxl, height: AppConfig.UI.trafficLightContainerHeight, alignment: .leading)
        // Non-fullscreen: align with traffic-light group (safeLeading + topInset).
        // Fullscreen: no traffic lights, align icon left edge with path-bar content (xxl).
        .padding(.leading, isFullScreen ? AppUI.Spacing.xxl : AppConfig.UI.trafficLightSafeLeading)
        .padding(.top, isFullScreen ? AppUI.Spacing.smMd : AppConfig.UI.trafficLightTopInset)
        .help("Show Sidebar (Cmd+B)")
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
        .offset(y: isFullScreen ? 0 : -4)
        .frame(maxWidth: 200, maxHeight: .infinity)
        .background(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = tab }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
