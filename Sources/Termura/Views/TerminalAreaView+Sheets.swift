import SwiftUI

// MARK: - Local UI State

/// Groups view-local state that only affects TerminalAreaView layout.
struct LocalUIState {
    var showExportSheet = false
    var showContextSheet = false
    var contextFileExists = false
    var metadataPanelWidth: Double = AppConfig.UI.metadataPanelWidth
}

// MARK: - Sheet modifiers

struct TerminalAreaSheets: ViewModifier {
    @Binding var riskAlert: RiskAlert?
    @Binding var contextWindowAlert: ContextWindowAlert?
    @Binding var showExportSheet: Bool
    @Binding var showContextSheet: Bool
    let engine: any TerminalEngine
    let sessionID: SessionID
    let sessionStore: SessionStore
    let outputStore: OutputStore
    let viewModel: TerminalViewModel

    func body(content: Content) -> some View {
        let eng = engine
        content
            .sheet(item: $riskAlert) { risk in
                InterventionAlertView(
                    alert: risk,
                    onProceed: { viewModel.dismissRiskAlert() },
                    onCancel: {
                        viewModel.dismissRiskAlert()
                        Task { await eng.send("\u{03}") }
                    }
                )
            }
            .sheet(item: $contextWindowAlert) { alert in
                ContextWindowAlertView(alert: alert) {
                    contextWindowAlert = nil
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let session = sessionStore.sessions
                    .first(where: { $0.id == sessionID }) {
                    ExportOptionsView(
                        session: session,
                        chunks: Array(outputStore.chunks),
                        isPresented: $showExportSheet
                    )
                }
            }
            .sheet(isPresented: $showContextSheet) {
                ContextFileView(
                    projectRoot: viewModel.currentMetadata.workingDirectory,
                    isPresented: $showContextSheet
                )
            }
    }
}
