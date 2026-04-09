import SwiftUI

// MARK: - Tokens

extension SessionMetadataBarView {
    var tokenSummarySection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("Tokens")
                Spacer()
                if !metadata.hasParsedTokenData {
                    Text("Updated each turn")
                        .font(AppUI.Font.micro)
                        .foregroundColor(.secondary.opacity(AppUI.Opacity.tertiary))
                }
            }
            if metadata.hasParsedTokenData {
                VStack(spacing: AppUI.Spacing.lg) {
                    tokenBar("Output", metadata.outputTokenCount)
                    tokenBar("Input", metadata.inputTokenCount)
                    tokenBar("Cache", metadata.cachedTokenCount)
                    if !subscriptionMode, metadata.estimatedCostUSD > 0 {
                        costRow
                    }
                }
            } else {
                Text("Available after first turn completes")
                    .font(AppUI.Font.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, AppUI.Spacing.xxs)
            }
        }
    }

    var costRow: some View {
        HStack(spacing: AppUI.Spacing.smMd) {
            Text("Cost")
                .font(AppUI.Font.micro)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            Spacer()
            Text(MetadataFormatter.formatCost(metadata.estimatedCostUSD))
                .font(AppUI.Font.captionMono)
                .foregroundColor(.primary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }

    func tokenBar(_ label: String, _ value: Int) -> some View {
        let hasValue = value > 0
        let maxTokens = max(
            metadata.inputTokenCount,
            metadata.outputTokenCount,
            metadata.cachedTokenCount,
            1
        )
        let fraction = min(Double(value) / Double(maxTokens), 1.0)
        let barColor = themeManager.current.foreground
        return HStack(spacing: AppUI.Spacing.smMd) {
            Text(label)
                .font(AppUI.Font.micro)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(AppUI.Opacity.whisper))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(hasValue ? barColor.opacity(AppUI.Opacity.secondary) : .clear)
                        .frame(width: max(geo.size.width * fraction, hasValue ? 2 : 0))
                }
            }
            .frame(height: 16)
            Text(hasValue ? MetadataFormatter.formatTokenCount(value) : "\u{2013}")
                .font(AppUI.Font.captionMono)
                .foregroundColor(hasValue ? .primary : .secondary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }

    var tokenRate: Int {
        guard metadata.agentElapsedTime > 60 else { return 0 }
        let total = metadata.inputTokenCount + metadata.outputTokenCount
        return Int(Double(total) / (metadata.agentElapsedTime / 60))
    }
}
