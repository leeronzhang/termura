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
    @Binding var contextWindowAlert: ContextWindowAlert?
    @Binding var showExportSheet: Bool
    @Binding var showContextSheet: Bool
    let sessionID: SessionID
    let sessionStore: SessionStore
    let outputStore: OutputStore
    let viewModel: TerminalViewModel

    func body(content: Content) -> some View {
        content
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
