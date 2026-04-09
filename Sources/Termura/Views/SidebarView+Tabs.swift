import AppKit
import SwiftUI

// MARK: - Agents Tab

extension SidebarView {
    @ViewBuilder
    var agentsContent: some View {
        AgentDashboardView(
            agentStore: sessionScope.agentStates,
            sessionTitles: sessionStore.sessionTitles
        ) { sid in
            sessionStore.activateSession(id: sid)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared Empty State

extension SidebarView {
    func sidebarEmptyState(icon: String, message: String) -> some View {
        VStack(spacing: AppUI.Spacing.smMd) {
            Image(systemName: icon)
                .font(AppUI.Font.hero)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
            Text(message)
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
