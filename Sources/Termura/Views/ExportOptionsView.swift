import AppKit
import SwiftUI

/// Sheet presented for session export — HTML or JSON format selection.
struct ExportOptionsView: View {
    let session: SessionRecord
    let chunks: [OutputChunk]
    @Binding var isPresented: Bool
    /// Injected for testability; defaults to the live implementation.
    let exportService: any SessionExportProtocol

    @State private var selectedFormat: ExportFormat = .html
    @State private var isExporting = false
    @State private var errorMessage: String?

    init(
        session: SessionRecord,
        chunks: [OutputChunk],
        isPresented: Binding<Bool>,
        exportService: any SessionExportProtocol = SessionExportService()
    ) {
        self.session = session
        self.chunks = chunks
        _isPresented = isPresented
        self.exportService = exportService
    }

    var body: some View {
        VStack(spacing: AppUI.Spacing.xl) {
            Text("Export Session")
                .font(.headline)

            Text(session.title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("Format", selection: $selectedFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.rawValue.uppercased()).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: AppConfig.UI.fieldPickerWidth)

            Text("\(chunks.count) output blocks")
                .font(.caption)
                .foregroundColor(.secondary)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack(spacing: AppUI.Spacing.lg) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button("Export") { performExport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExporting || chunks.isEmpty)
            }
        }
        .padding(AppUI.Spacing.xxxl)
        .frame(width: AppConfig.UI.exportOptionsSheetWidth)
    }

    private func performExport() {
        isExporting = true
        errorMessage = nil
        Task { @MainActor in
            defer { isExporting = false }
            do {
                let url: URL = switch selectedFormat {
                case .html:
                    try await exportService.exportHTML(session: session, chunks: chunks)
                case .json:
                    try await exportService.exportJSON(session: session, chunks: chunks)
                }
                isPresented = false
                revealInFinder(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
