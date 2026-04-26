import SwiftUI

/// Lightweight bottom-of-window toast banner for cross-cutting status messages
/// (e.g. AI commit success/failure). Mirrors the visual style of the notes
/// silent-capture toast in `TerminalAreaView+Overlays.swift`.
struct ToastBannerView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(AppUI.Font.bodyMedium)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppUI.Spacing.xxl)
            .padding(.vertical, AppUI.Spacing.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppUI.Spacing.md))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
    }
}

#if DEBUG
#Preview {
    ToastBannerView(message: "Committed: feat: add commit popover")
        .frame(width: 600, height: 100)
}
#endif
