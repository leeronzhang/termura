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
    @Binding var showExportSheet: Bool
    @Binding var showContextSheet: Bool
    let sessionID: SessionID
    let sessionStore: SessionStore
    let outputStore: OutputStore
    let viewModel: TerminalViewModel
    let projectRoot: String

    func body(content: Content) -> some View {
        content
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
                    projectRoot: projectRoot,
                    isPresented: $showContextSheet
                )
            }
    }
}
