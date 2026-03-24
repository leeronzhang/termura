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
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 500, minHeight: 300)
            }

            Divider()
            footer
        }
        .frame(minWidth: 550, minHeight: 400)
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
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = contextFilePath
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func loadFile() {
        do {
            content = try String(contentsOfFile: contextFilePath, encoding: .utf8)
        } catch {
            errorMessage = "Could not read context.md: \(error.localizedDescription)"
        }
    }

    private func saveFile() {
        isSaving = true
        defer { isSaving = false }

        let dirPath = (projectRoot as NSString)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
        do {
            if !FileManager.default.fileExists(atPath: dirPath) {
                try FileManager.default.createDirectory(
                    atPath: dirPath,
                    withIntermediateDirectories: true
                )
            }
            try content.write(toFile: contextFilePath, atomically: true, encoding: .utf8)
            isPresented = false
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
