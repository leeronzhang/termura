import SwiftUI

/// Sheet view for viewing and editing the project's `.termura/context.md` file.
struct ContextFileView: View {
    @Environment(\.fileManager) private var fileManager
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
                    .accessibilityLabel("Context file content")
                    .accessibilityHint("Edit the project context document")
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
                .accessibilityHidden(true)
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
                .accessibilityHint("Closes without saving changes")

            Spacer()

            Button("Save") { saveFile() }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || errorMessage != nil)
                .accessibilityHint("Saves changes to context.md on disk")
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
            // WHY: Reading context.md must not block MainActor.
            // OWNER: loadFile owns this detached read and awaits it inline.
            // TEARDOWN: The detached task exits after one read attempt.
            // TEST: Cover successful context load and read-failure reporting.
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
        let fileManager = fileManager
        // Lifecycle: user-initiated save — even if sheet dismisses, the write finishes harmlessly.
        // Task { } inherits @MainActor from the View; I/O is offloaded via inner Task.detached
        // so the main thread is not blocked, and state updates after the await are safely on MainActor.
        Task {
            do {
                let root = projectRoot
                // WHY: Saving context.md may create directories and write files, so it must leave MainActor.
                // OWNER: The enclosing Task owns this detached write and awaits it before updating save state.
                // TEARDOWN: The detached task ends after one save attempt and does not outlive saveFile().
                // TEST: Cover gitignore repair, directory creation, and context save success/failure.
                try await Task.detached {
                    // Ensure .termura/ is in .gitignore before creating the directory,
                    // preventing accidental commit of AI session data.
                    let rootURL = URL(fileURLWithPath: root)
                    ensureProjectGitignore(at: rootURL, fileManager: fileManager)
                    if !fileManager.fileExists(atPath: dirPath) {
                        try fileManager.createDirectory(
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
