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
        case .sessions: "terminal"
        case .agents: "poweroutlet.type.f"
        case .harness: "pano"
        case .notes: "text.rectangle"
        case .project: "folder"
        }
    }

    var activeIcon: String {
        switch self {
        case .sessions: "terminal.fill"
        case .agents: "poweroutlet.type.f.fill"
        case .harness: "pano.fill"
        case .notes: "text.rectangle.fill"
        case .project: "folder.fill"
        }
    }

    var label: String {
        switch self {
        case .sessions: "Sessions"
        case .agents: "Agents"
        case .harness: "Harness"
        case .notes: "Notes"
        case .project: "Project"
        }
    }
}

/// Xcode-style icon tab bar for sidebar navigation.
struct SidebarTabBar: View {
    @Binding var selectedTab: SidebarTab
    var isFullScreen: Bool = false
    var hasUncommittedChanges: Bool = false
    /// Non-zero when the project has active compiler/linter errors.
    /// Shows a red badge dot on the project tab, taking visual priority over the blue
    /// uncommitted-changes dot so the more actionable state is always visible.
    var diagnosticErrorCount: Int = 0

    /// Extra leading space to clear the traffic-light buttons in non-fullscreen.
    /// Derived from the measured container position and width so it stays correct
    /// across macOS versions without hardcoding.
    private var trafficLightLeading: CGFloat { isFullScreen ? 0 : AppConfig.UI.trafficLightSafeLeading }

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

    private func tabAccessibilityValue(_ tab: SidebarTab) -> String {
        guard tab == .project else { return "" }
        if diagnosticErrorCount > 0 {
            return "\(diagnosticErrorCount) error\(diagnosticErrorCount == 1 ? "" : "s")"
        } else if hasUncommittedChanges {
            return "Uncommitted changes"
        }
        return ""
    }

    private func tabButton(_ tab: SidebarTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: selectedTab == tab ? tab.activeIcon : tab.icon)
                    .font(AppUI.Font.tabBarIcon)
                    .foregroundColor(selectedTab == tab ? .brandGreen : .secondary)

                if tab == .project && diagnosticErrorCount > 0 {
                    // Errors take priority — red dot replaces the uncommitted-changes dot.
                    Circle()
                        .fill(Color.red)
                        .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                        .offset(x: 3, y: -1)
                } else if tab == .project && hasUncommittedChanges {
                    Circle()
                        .fill(Color.brandGreen)
                        .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                        .offset(x: 3, y: -1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: AppUI.Spacing.xxxxl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(tab.label)
        .accessibilityLabel(tab.label)
        .accessibilityValue(tabAccessibilityValue(tab))
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }
}
