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
        .padding(.horizontal, AppUI.Spacing.md)
        .padding(.top, isFullScreen ? AppUI.Spacing.smMd : 8)
        .padding(.bottom, AppUI.Spacing.smMd)
        .padding(.leading, trafficLightLeading)
        .animation(.easeInOut(duration: 0.25), value: isFullScreen)
    }

    private func tabButton(_ tab: SidebarTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: selectedTab == tab ? tab.activeIcon : tab.icon)
                    .font(.system(size: 15))
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)

                if tab == .project && hasUncommittedChanges {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: -2, y: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.label)
    }
}
