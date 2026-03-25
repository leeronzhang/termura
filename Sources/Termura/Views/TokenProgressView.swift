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

            HStack {
                Text(formattedTokens)
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary)
                Spacer()
                Text(percentageText)
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(isWarning ? .orange : .secondary)
            }
        }
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
