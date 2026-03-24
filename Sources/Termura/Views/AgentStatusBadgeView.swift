import SwiftUI

/// Small badge indicating an agent's operational status.
/// Used in the sidebar next to session rows.
struct AgentStatusBadgeView: View {
    let status: AgentStatus
    let agentType: AgentType

    var body: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            statusDot
            if status == .thinking || status == .toolRunning {
                pulsingIndicator
            }
        }
        .help(helpText)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: AppUI.Size.dotMedium, height: AppUI.Size.dotMedium)
    }

    @ViewBuilder
    private var pulsingIndicator: some View {
        Circle()
            .fill(statusColor.opacity(0.4))
            .frame(width: AppUI.Size.dotMedium, height: AppUI.Size.dotMedium)
            .scaleEffect(1.5)
            .opacity(AppUI.Opacity.secondary)
    }

    private var statusColor: Color {
        switch status {
        case .idle: .gray
        case .thinking: .blue
        case .toolRunning: .orange
        case .waitingInput: .yellow
        case .error: .red
        case .completed: .green
        }
    }

    private var helpText: String {
        "\(agentType.rawValue) — \(status.rawValue)"
    }
}
