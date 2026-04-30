import SwiftUI

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
                        .accessibilityHidden(true)
                } else if hasUncommittedChanges {
                    Circle()
                        .fill(Color.brandGreen)
                        .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                        .offset(x: 3, y: -1)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        // Horizontal: alignment .leading anchors the icon's left edge at the padding origin
        // (matching projectPathBar leading content); the extra frame width is right-side hit area.
        // Vertical:
        //   - Non-fullscreen: top padding = trafficLightTopInset places the icon next to the
        //     traffic-light buttons (the visible reference in this mode).
        //   - Fullscreen: no traffic lights — give the button the full contentTabBarHeight so
        //     it vertically centers with the tab labels (which occupy the same height).
        .frame(
            width: AppUI.Spacing.xxxxl,
            height: isFullScreen ? AppConfig.UI.contentTabBarHeight : nil,
            alignment: .leading
        )
        .padding(.leading, isFullScreen ? AppUI.Spacing.xxl : AppConfig.UI.trafficLightSafeLeading)
        .padding(.top, isFullScreen ? 0 : AppConfig.UI.trafficLightTopInset)
        .help("Show Sidebar (Cmd+B)")
        .accessibilityLabel(sidebarRevealAccessibilityLabel)
    }

    private var sidebarRevealAccessibilityLabel: String {
        if diagnosticErrorCount > 0 {
            return "Show Sidebar, \(diagnosticErrorCount) error\(diagnosticErrorCount == 1 ? "" : "s")"
        } else if hasUncommittedChanges {
            return "Show Sidebar, uncommitted changes"
        }
        return "Show Sidebar"
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
                .accessibilityHidden(true)
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
                    .accessibilityHidden(true)
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
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(.default) { selectedTab = tab }
        .accessibilityAction(named: "Close Tab") { onClose(tab) }
    }
}
