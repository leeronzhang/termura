import SwiftUI

/// Sheet view for viewing and editing the project's `.termura/context.md` file.
struct ContextFileView: View {
    let projectRoot: String
    @Binding var isPresented: Bool

    @State private var content: String = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var contextFilePath: String {
        URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appendingPathComponent(AppConfig.SessionHandoff.contextFileName).path
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let error = errorMessage {
                errorView(error)
            } else {
                TextEditor(text: $content)
                    .font(AppUI.Font.bodyMono)
                    .frame(minWidth: AppConfig.UI.contextFileMinWidth, minHeight: AppConfig.UI.contextFileMinHeight)
            }

            Divider()
            footer
        }
        .frame(minWidth: AppConfig.UI.contextFileEditMinWidth, minHeight: AppConfig.UI.contextFileEditMinHeight)
        .task { await loadFile() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.text")
            Text("context.md")
                .font(.headline)
            Spacer()
            Text(abbreviatedPath)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(AppUI.Spacing.md)
    }

    private var footer: some View {
        HStack {
            Button("Dismiss") { isPresented = false }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Save") { saveFile() }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || errorMessage != nil)
        }
        .padding(AppUI.Spacing.md)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppUI.Spacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(message)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var abbreviatedPath: String {
        let home = AppConfig.Paths.homeDirectory
        let path = contextFilePath
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func loadFile() async {
        let path = contextFilePath
        do {
            let text = try await Task.detached {
                try String(contentsOfFile: path, encoding: .utf8)
            }.value
            content = text
        } catch {
            errorMessage = "Could not read context.md: \(error.localizedDescription)"
        }
    }

    private func saveFile() {
        isSaving = true
        let dirPath = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName).path
        let filePath = contextFilePath
        let text = content
        // Lifecycle: user-initiated save — even if sheet dismisses, the write finishes harmlessly.
        // Task { } inherits @MainActor from the View; I/O is offloaded via inner Task.detached
        // so the main thread is not blocked, and state updates after the await are safely on MainActor.
        Task {
            do {
                try await Task.detached {
                    if !FileManager.default.fileExists(atPath: dirPath) {
                        try FileManager.default.createDirectory(
                            atPath: dirPath, withIntermediateDirectories: true
                        )
                    }
                    try text.write(toFile: filePath, atomically: true, encoding: .utf8)
                }.value
                isSaving = false
                isPresented = false
            } catch {
                isSaving = false
                errorMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }
}
