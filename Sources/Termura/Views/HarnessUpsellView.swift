import AppKit
import SwiftUI

// MARK: - Free-build upsell

/// Shown in place of real harness content when HARNESS_ENABLED is not set.
/// Explains the feature and links to the product page.
#if !HARNESS_ENABLED
struct HarnessUpsellView: View {
    private struct Feature {
        let icon: String
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        Feature(
            icon: "doc.text.magnifyingglass",
            title: "Rule File Management",
            detail: "Browse and version-track AGENTS.md and CLAUDE.md across all your projects."
        ),
        Feature(
            icon: "sparkle.magnifyingglass",
            title: "Corruption Detection",
            detail: "Scan rule files for structural issues and conflicting directives before they mislead your AI agent."
        ),
        Feature(
            icon: "wand.and.sparkles",
            title: "Experience Codification",
            detail: "Turn agent errors and successful patterns into durable rules with one click."
        ),
        Feature(
            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            title: "Version History",
            detail: "See every change to a rule file, diff between versions, and roll back instantly."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppUI.Spacing.xl) {
                    tagline
                    featureList
                    ctaButton
                }
                .padding(.horizontal, AppUI.Spacing.xxxl)
                .padding(.vertical, AppUI.Spacing.xl)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Harness")
                .panelHeaderStyle()
            Spacer()
            Text("PRO")
                .font(AppUI.Font.captionMono)
                .foregroundColor(.white)
                .padding(.horizontal, AppUI.Spacing.smMd)
                .padding(.vertical, 2)
                .background(Color.brandGreen)
                .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.sm))
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    private var tagline: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            Text("Keep your AI agents on track.")
                .font(AppUI.Font.title3Medium)
                .foregroundColor(.primary)
            Text("Harness turns hard-won prompt engineering into permanent, versioned rules — so every agent session starts smarter.")
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.lg) {
            ForEach(features, id: \.title) { feature in
                HStack(alignment: .top, spacing: AppUI.Spacing.mdLg) {
                    Image(systemName: feature.icon)
                        .font(AppUI.Font.body)
                        .foregroundColor(.brandGreen)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                        Text(feature.title)
                            .font(AppUI.Font.labelMedium)
                            .foregroundColor(.primary)
                        Text(feature.detail)
                            .font(AppUI.Font.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var ctaButton: some View {
        Button {
            guard let url = URL(string: AppConfig.URLs.harnessProduct) else { return }
            NSWorkspace.shared.open(url)
        } label: {
            HStack {
                Spacer()
                Text("Learn More & Upgrade")
                    .font(AppUI.Font.labelMedium)
                Image(systemName: "arrow.up.right")
                    .font(AppUI.Font.caption)
                Spacer()
            }
            .padding(.vertical, AppUI.Spacing.smMd)
            .background(Color.brandGreen)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
        }
        .buttonStyle(.plain)
    }
}
#endif
