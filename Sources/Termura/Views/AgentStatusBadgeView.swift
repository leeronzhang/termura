import SwiftUI

/// Small badge indicating an agent's operational status.
/// Used in the sidebar next to session rows.
struct AgentStatusBadgeView: View {
    let status: AgentStatus
    let agentType: AgentType

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
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
            .frame(width: DS.Size.dotMedium, height: DS.Size.dotMedium)
    }

    @ViewBuilder
    private var pulsingIndicator: some View {
        Circle()
            .fill(statusColor.opacity(0.4))
            .frame(width: DS.Size.dotMedium, height: DS.Size.dotMedium)
            .scaleEffect(1.5)
            .opacity(DS.Opacity.secondary)
    }

    private var statusColor: Color {
        switch status {
        case .idle: return .gray
        case .thinking: return .blue
        case .toolRunning: return .orange
        case .waitingInput: return .yellow
        case .error: return .red
        case .completed: return .green
        }
    }

    private var helpText: String {
        "\(agentType.rawValue) — \(status.rawValue)"
    }
}
