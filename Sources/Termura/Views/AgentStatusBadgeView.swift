import SwiftUI

/// Small badge indicating an agent's operational status.
/// Used in the sidebar next to session rows.
struct AgentStatusBadgeView: View {
    let status: AgentStatus
    let agentType: AgentType

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: AppUI.Size.dotMedium, height: AppUI.Size.dotMedium)
            .overlay(pulsingOverlay)
            .help(helpText)
            .onAppear { updatePulse() }
            .onChange(of: status) { _, _ in updatePulse() }
            .accessibilityLabel("\(agentType.displayName): \(status.rawValue)")
            .accessibilityValue(helpText)
    }

    @ViewBuilder
    private var pulsingOverlay: some View {
        if status == .thinking || status == .toolRunning {
            Circle()
                .stroke(statusColor.opacity(0.5), lineWidth: 1.5)
                .frame(
                    width: AppUI.Size.dotMedium * 2,
                    height: AppUI.Size.dotMedium * 2
                )
                .scaleEffect(isPulsing ? AppUI.Scale.pulseMax : AppUI.Scale.pulseMin)
                .opacity(isPulsing ? 0.0 : 0.6)
        }
    }

    private func updatePulse() {
        let shouldPulse = status == .thinking || status == .toolRunning
        if shouldPulse {
            withAnimation(
                .easeInOut(duration: AppUI.Animation.pulse).repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        } else {
            // Wrap in withAnimation to interrupt the Core Animation repeatForever layer.
            // Without this, CA may continue driving the animation after the view value change.
            withAnimation(.easeOut(duration: AppUI.Animation.fadeOut)) {
                isPulsing = false
            }
        }
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
        "\(agentType.displayName) — \(status.rawValue)"
    }
}

#if DEBUG
#Preview("Agent Status Badges") {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(AgentStatus.allCases, id: \.self) { status in
            HStack(spacing: 12) {
                AgentStatusBadgeView(status: status, agentType: .claudeCode)
                Text(status.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    .padding()
}
#endif
