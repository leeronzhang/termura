import SwiftUI

/// Sidebar navigation tabs, inspired by Xcode's navigator tab bar.
enum SidebarTab: String, CaseIterable, Identifiable {
    case sessions
    case agents
    case harness
    case notes
    case search

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sessions: return "terminal"
        case .agents: return "poweroutlet.type.f"
        case .search: return "magnifyingglass"
        case .notes: return "text.page"
        case .harness: return "pano"
        }
    }

    var activeIcon: String {
        switch self {
        case .sessions: return "terminal.fill"
        case .agents: return "poweroutlet.type.f.fill"
        case .search: return "magnifyingglass"
        case .notes: return "text.page.fill"
        case .harness: return "pano.fill"
        }
    }

    var label: String {
        switch self {
        case .sessions: return "Sessions"
        case .agents: return "Agents"
        case .search: return "Search"
        case .notes: return "Notes"
        case .harness: return "Harness"
        }
    }
}

/// Xcode-style icon tab bar for sidebar navigation.
struct SidebarTabBar: View {
    @Binding var selectedTab: SidebarTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SidebarTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, AppUI.Spacing.md)
        .padding(.vertical, AppUI.Spacing.smMd)
    }

    private func tabButton(_ tab: SidebarTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Image(systemName: selectedTab == tab ? tab.activeIcon : tab.icon)
                .font(.system(size: 15))
                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.label)
    }
}
