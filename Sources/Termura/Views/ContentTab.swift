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
            }
            Spacer()
        }
        .padding(.top, titleBarTop)
        .frame(height: 44 + titleBarTop)
        .background(Color.black.opacity(0.25))
    }

    private func tabButton(_ tab: ContentTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: AppUI.Spacing.sm) {
                Image(systemName: tab.icon)
                    .font(AppUI.Font.caption)
                Text(tab.title)
                    .font(AppUI.Font.label)
                    .lineLimit(1)
                Spacer()
                Button {
                    onClose(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(AppUI.Font.micro)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .padding(.horizontal, 18)
            .frame(maxWidth: 200, maxHeight: .infinity)
            .background(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
