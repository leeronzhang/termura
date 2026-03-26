import SwiftUI

/// Bottom sheet composer within the terminal area.
/// Slides up from the bottom, same width as the terminal.
struct ComposerOverlayView: View {
    @ObservedObject var editorViewModel: EditorViewModel
    var notesViewModel: NotesViewModel
    let editorHandle: EditorViewHandle
    let onDismiss: () -> Void

    enum Tab { case compose, snippets }
    @State private var activeTab: Tab = .compose
    @State private var snippetSearch: String = ""
    @State private var showSaveConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            cardContent
            cardFooter
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .frame(height: AppConfig.UI.composerMaxHeight)
        .onAppear {
            Task { await notesViewModel.loadSnippets() }
            focusEditor()
        }
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(spacing: AppUI.Spacing.lgXl) {
            tabLabel("Compose", tab: .compose)
            tabLabel("Snippets", tab: .snippets)
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: AppConfig.UI.composerCloseIconSize))
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.vertical, AppUI.Spacing.lgXl)
    }

    private func tabLabel(_ title: String, tab: Tab) -> some View {
        let isActive = activeTab == tab
        return Button {
            withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
                activeTab = tab
                if tab == .compose { focusEditor() }
            }
        } label: {
            Text(title)
                .font(isActive ? AppUI.Font.labelMedium : AppUI.Font.label)
                .foregroundColor(isActive ? .primary : .secondary)
                .overlay(alignment: .bottom) {
                    if isActive {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .offset(y: 4)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var cardContent: some View {
        switch activeTab {
        case .compose:
            EditorInputView(viewModel: editorViewModel, viewHandle: editorHandle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppUI.Spacing.xxl)
                .padding(.vertical, AppUI.Spacing.lgXl)
        case .snippets:
            ComposerSnippetsView(
                editorViewModel: editorViewModel,
                notesViewModel: notesViewModel,
                snippetSearch: $snippetSearch,
                onSwitchToCompose: { switchToCompose() },
                onDismiss: onDismiss
            )
        }
    }

    // MARK: - Footer

    private var cardFooter: some View {
        HStack(spacing: AppUI.Spacing.md) {
            if activeTab == .compose {
                saveSnippetButton
                Spacer()
                Text("Cmd+Enter to send")
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
                sendButton
            } else {
                Text("Click to edit, arrow to send")
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
                Spacer()
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.vertical, AppUI.Spacing.lgXl)
    }

    private var saveSnippetButton: some View {
        Button {
            let text = editorViewModel.currentText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let firstLine = text.components(separatedBy: .newlines).first ?? text
            notesViewModel.createSnippet(title: firstLine, body: text)
            showSaveConfirm = true
            Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: AppConfig.UI.saveConfirmDurationNanoseconds)
                } catch {
                    // Non-critical: UI confirmation badge dismissed early on cancellation.
                    return
                }
                showSaveConfirm = false
            }
        } label: {
            Label(
                showSaveConfirm ? "Saved" : "Save Snippet",
                systemImage: showSaveConfirm ? "checkmark" : "bookmark"
            )
            .font(AppUI.Font.captionMono)
            .foregroundColor(showSaveConfirm ? .green : .primary)
            .padding(.horizontal, AppUI.Spacing.lg)
            .padding(.vertical, AppUI.Spacing.smMd)
            .background(Capsule().fill(Color.secondary.opacity(AppUI.Opacity.tint)))
        }
        .buttonStyle(.plain)
        .disabled(editorViewModel.currentText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var sendButton: some View {
        Button {
            editorViewModel.submit()
            onDismiss()
        } label: {
            Label("Send", systemImage: "paperplane.fill")
                .font(AppUI.Font.labelMedium)
                .foregroundColor(.white)
                .padding(.horizontal, AppUI.Spacing.lgXl)
                .padding(.vertical, AppUI.Spacing.smMd)
                .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .disabled(editorViewModel.currentText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - Focus

    private func focusEditor() {
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: AppConfig.UI.editorFocusDelayNanoseconds)
            } catch {
                // Non-critical: focus attempt is cosmetic; user can click the editor manually.
                return
            }
            guard let textView = editorHandle.textView,
                  let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }

    private func switchToCompose() {
        withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
            activeTab = .compose
        }
        focusEditor()
    }
}
