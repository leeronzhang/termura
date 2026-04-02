import SwiftUI

/// Token consumption progress bar with context window percentage.
/// Shows estimated token usage relative to the agent's context limit.
struct TokenProgressView: View {
    let estimatedTokens: Int
    let contextLimit: Int

    private var fraction: Double {
        guard contextLimit > 0 else { return 0 }
        return min(Double(estimatedTokens) / Double(contextLimit), 1.0)
    }

    private var isWarning: Bool {
        fraction >= AppConfig.UI.tokenProgressWarningFraction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            ProgressView(value: fraction, total: 1.0)
                .progressViewStyle(.linear)
                .tint(progressColor)
                .clipShape(Rectangle())
                .accessibilityHidden(true)

            HStack {
                Text(formattedTokens)
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary)
                Spacer()
                Text(percentageText)
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(isWarning ? .orange : .secondary)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context window usage")
        .accessibilityValue("\(formattedTokens) tokens, \(percentageText)")
    }

    private var progressColor: Color {
        if fraction >= AppConfig.UI.tokenProgressCriticalFraction { return .red }
        if fraction >= AppConfig.UI.tokenProgressWarningFraction { return .orange }
        return .accentColor
    }

    private var formattedTokens: String {
        if estimatedTokens >= 1000 {
            return String(format: "%.1fk", Double(estimatedTokens) / 1000)
        }
        return "\(estimatedTokens)"
    }

    private var percentageText: String {
        String(format: "%.0f%%", fraction * 100)
    }
}

#if DEBUG
#Preview("Token Progress") {
    VStack(spacing: 24) {
        Group {
            TokenProgressView(estimatedTokens: 0, contextLimit: 200_000)
            TokenProgressView(estimatedTokens: 50000, contextLimit: 200_000)
            TokenProgressView(estimatedTokens: 160_000, contextLimit: 200_000)
            TokenProgressView(estimatedTokens: 195_000, contextLimit: 200_000)
        }
        .frame(width: 240)
    }
    .padding()
}
#endif
