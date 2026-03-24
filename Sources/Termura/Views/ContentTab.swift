import SwiftUI

/// Identifies an open tab in the main content area.
enum ContentTab: Identifiable, Hashable {
    case terminal
    case note(NoteID, String)

    var id: String {
        switch self {
        case .terminal: return "terminal"
        case .note(let noteID, _): return "note-\(noteID)"
        }
    }

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .note(_, let name): return name.isEmpty ? "Untitled" : name
        }
    }

    var icon: String {
        switch self {
        case .terminal: return "terminal"
        case .note: return "doc.text"
        }
    }

    /// Terminal tab cannot be closed.
    var isClosable: Bool {
        switch self {
        case .terminal: return false
        case .note: return true
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
    private var titleBarTop: CGFloat { isFullScreen ? 0 : 6 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabButton(tab)
                if tab != tabs.last {
                    Divider().frame(height: 14)
                }
            }
            Spacer()
        }
        .padding(.top, titleBarTop)
        .frame(height: 44 + titleBarTop)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tabButton(_ tab: ContentTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: AppUI.Spacing.sm) {
                Image(systemName: tab.icon)
                    .font(AppUI.Font.caption)
                Text(tab.title)
                    .font(AppUI.Font.label)
                    .lineLimit(1)
                Button {
                    onClose(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(AppUI.Font.micro)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(selectedTab == tab ? .primary : .secondary)
            .padding(.horizontal, AppUI.Spacing.lg)
            .frame(maxHeight: .infinity)
            .background(selectedTab == tab ? Color.white.opacity(AppUI.Opacity.whisper) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
