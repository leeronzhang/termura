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
        // alignment: .leading so the icon's left edge sits exactly at the padding origin,
        // matching the leading edge of projectPathBar content (xxl = 20pt).
        // The extra frame width beyond the icon provides hit-area padding to the right.
        // Vertically center with traffic-light buttons: icon top at trafficLightTopInset (17pt),
        // icon center at ~24pt = traffic-light center (topInset + buttonHeight/2).
        .frame(width: AppUI.Spacing.xxxxl, alignment: .leading)
        .padding(.leading, isFullScreen ? AppUI.Spacing.xxl : AppConfig.UI.trafficLightSafeLeading)
        .padding(.top, isFullScreen ? AppUI.Spacing.smMd : AppConfig.UI.trafficLightTopInset)
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
