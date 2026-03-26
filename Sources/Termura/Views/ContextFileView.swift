import SwiftUI

/// Sheet view for viewing and editing the project's `.termura/context.md` file.
struct ContextFileView: View {
    let projectRoot: String
    @Binding var isPresented: Bool

    @State private var content: String = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var contextFilePath: String {
        (projectRoot as NSString)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appending("/\(AppConfig.SessionHandoff.contextFileName)")
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
        .onAppear { loadFile() }
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

    private func loadFile() {
        let path = contextFilePath
        Task.detached {
            do {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                await MainActor.run { content = text }
            } catch {
                let msg = "Could not read context.md: \(error.localizedDescription)"
                await MainActor.run { errorMessage = msg }
            }
        }
    }

    private func saveFile() {
        isSaving = true
        let dirPath = (projectRoot as NSString)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
        let filePath = contextFilePath
        let text = content
        Task.detached {
            do {
                if !FileManager.default.fileExists(atPath: dirPath) {
                    try FileManager.default.createDirectory(
                        atPath: dirPath, withIntermediateDirectories: true)
                }
                try text.write(toFile: filePath, atomically: true, encoding: .utf8)
                await MainActor.run {
                    isSaving = false
                    isPresented = false
                }
            } catch {
                let msg = "Save failed: \(error.localizedDescription)"
                await MainActor.run {
                    isSaving = false
                    errorMessage = msg
                }
            }
        }
    }
}
