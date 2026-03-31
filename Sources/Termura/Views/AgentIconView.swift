import SwiftUI

/// Renders agent brand icons as SwiftUI shapes using embedded SVG path data.
/// No external font or image assets required — paths extracted from RemixIcon (Apache 2.0).
struct AgentIconView: View {
    let agentType: AgentType
    var size: CGFloat = 14
    /// When false (e.g. restored from DB, no live agent), renders in gray.
    var isActive: Bool = true

    private var inactiveColor: Color { .secondary }

    var body: some View {
        icon
            .accessibilityLabel(agentType.displayName)
    }

    @ViewBuilder
    private var icon: some View {
        switch agentType {
        case .claudeCode:
            ClaudeIconShape()
                .fill(isActive ? Color.orange : inactiveColor)
                .frame(width: size, height: size)
        case .codex:
            OpenAIIconShape()
                .fill(isActive ? Color.primary : inactiveColor)
                .frame(width: size, height: size)
        case .gemini:
            GeminiIconShape()
                .fill(isActive ? Color.blue : inactiveColor)
                .frame(width: size, height: size)
        case .aider:
            GenericAgentIconShape()
                .stroke(isActive ? Color.purple : inactiveColor, lineWidth: 1.5)
                .frame(width: size, height: size)
        case .openCode:
            GenericAgentIconShape()
                .stroke(isActive ? Color.cyan : inactiveColor, lineWidth: 1.5)
                .frame(width: size, height: size)
        case .pi:
            GenericAgentIconShape()
                .stroke(isActive ? Color.pink : inactiveColor, lineWidth: 1.5)
                .frame(width: size, height: size)
        case .unknown:
            Image(systemName: "terminal")
                .font(.system(size: size * AppConfig.UI.agentIconScaleFactor))
                .foregroundColor(.secondary)
        }
    }
}

#if DEBUG
#Preview("Agent Icons") {
    VStack(alignment: .leading, spacing: 20) {
        ForEach(AgentType.allCases, id: \.self) { type in
            HStack(spacing: 16) {
                AgentIconView(agentType: type, size: 20, isActive: true)
                AgentIconView(agentType: type, size: 20, isActive: false)
                Text(type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    .padding()
}
#endif
