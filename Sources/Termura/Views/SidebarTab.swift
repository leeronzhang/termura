import SwiftUI

/// Sidebar navigation tabs, inspired by Xcode's navigator tab bar.
enum SidebarTab: String, CaseIterable, Identifiable {
    case sessions
    case agents
    case harness
    case notes
    case project

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sessions: return "terminal"
        case .agents: return "poweroutlet.type.f"
        case .notes: return "text.rectangle"
        case .harness: return "pano"
        case .project: return "folder"
        }
    }

    var activeIcon: String {
        switch self {
        case .sessions: return "terminal.fill"
        case .agents: return "poweroutlet.type.f.fill"
        case .notes: return "text.rectangle.fill"
        case .harness: return "pano.fill"
        case .project: return "folder.fill"
        }
    }

    var label: String {
        switch self {
        case .sessions: return "Sessions"
        case .agents: return "Agents"
        case .notes: return "Notes"
        case .harness: return "Harness"
        case .project: return "Project"
        }
    }
}

/// Xcode-style icon tab bar for sidebar navigation.
struct SidebarTabBar: View {
    @Binding var selectedTab: SidebarTab
    var isFullScreen: Bool = false
    var hasUncommittedChanges: Bool = false

    /// Extra leading space to clear the traffic-light buttons in non-fullscreen.
    private var trafficLightLeading: CGFloat { isFullScreen ? 0 : 80 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SidebarTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 0)
        .padding(.top, isFullScreen ? AppUI.Spacing.smMd : AppUI.Spacing.md)
        .padding(.bottom, AppUI.Spacing.smMd)
        .padding(.leading, trafficLightLeading)
        .animation(.easeInOut(duration: AppUI.Animation.tabSwitch), value: isFullScreen)
    }

    private func tabButton(_ tab: SidebarTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: selectedTab == tab ? tab.activeIcon : tab.icon)
                    .font(AppUI.Font.tabBarIcon)
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)

                if tab == .project && hasUncommittedChanges {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                        .offset(x: 3, y: -1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: AppUI.Spacing.xxxxl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.label)
    }
}
