import SwiftUI

// MARK: - Bottom overlays

extension TerminalAreaView {
    /// Notes silent-capture toast — only shown in the focused pane in dual-pane mode.
    @ViewBuilder
    var notesOverlay: some View {
        if let message = notesViewModel.toastMessage,
           !commandRouter.isDualPaneActive || isFocusedPane {
            Button {
                notesViewModel.toastMessage = nil
                commandRouter.pendingCommand = .openLastSilentNote
            } label: {
                Text(message)
                    .font(AppUI.Font.bodyMedium)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppUI.Spacing.xxl)
                    .padding(.vertical, AppUI.Spacing.md)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppUI.Spacing.md))
            }
            .buttonStyle(.plain)
            .padding(.bottom, AppUI.Spacing.xxl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    var riskAlertOverlay: some View {
        if let risk = state.viewModel.pendingRiskAlert {
            RiskAlertBannerView(
                alert: risk,
                onStopAgent: {
                    state.viewModel.dismissRiskAlert()
                    let eng = engine
                    Task { await eng.send("\u{03}") }
                },
                onAllow: { state.viewModel.dismissRiskAlert() }
            )
        }
    }

    @ViewBuilder
    var contextWindowOverlay: some View {
        if let alert = state.viewModel.contextWindowAlert {
            ContextWindowAlertView(alert: alert) {
                state.viewModel.contextWindowAlert = nil
            }
        }
    }
}
