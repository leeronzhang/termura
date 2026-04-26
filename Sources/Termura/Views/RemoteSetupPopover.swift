import Foundation
import OSLog
import SwiftUI

private let popoverLogger = Logger(subsystem: "com.termura.app", category: "RemoteSetupPopover")

/// Anchored popover from the bottom-bar remote indicator. Shows the current remote
/// configuration (or absence) and lets the user describe a desired change in plain
/// language — the AI agent runs the actual `git remote` commands headless.
struct RemoteSetupPopover: View {
    @Environment(\.commandRouter) private var commandRouter
    @Environment(\.sessionScope) private var sessionScope
    @Environment(\.projectScope) private var projectScope

    @Binding var isPresented: Bool
    let projectRoot: URL
    let currentRemoteURL: String?
    let currentRemoteHost: String?

    @State private var note: String = ""

    @State private var detectedAgent: AgentType?
    @State private var detectedSessionLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
            AICommitPopoverHeader(agent: detectedAgent, sessionLabel: detectedSessionLabel)
            currentStateSection
            noteSection
            AICommitPopoverFooter(
                primaryLabel: currentRemoteURL == nil ? "Set Up Remote" : "Apply",
                primaryEnabled: canSubmit,
                onCancel: { isPresented = false },
                onPrimary: submit
            )
        }
        .frame(width: 420)
        .padding(.vertical, AppUI.Spacing.xs)
        .background(
            // Tight 2pt radius — see CommitPopover for the platform-radius caveat.
            RoundedRectangle(cornerRadius: AppUI.Spacing.xs)
                .fill(Color.clear)
        )
        .onAppear { onAppear() }
    }

    // MARK: - Sections

    private var currentStateSection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
            Text("Current remote")
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary)
            if let url = currentRemoteURL {
                HStack(spacing: AppUI.Spacing.sm) {
                    Text(url)
                        .font(AppUI.Font.captionMono)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let host = currentRemoteHost {
                        Text("(\(host))")
                            .font(AppUI.Font.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No remote configured")
                    .font(AppUI.Font.caption)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppUI.Spacing.lg)
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
            Text(currentRemoteURL == nil
                ? "Describe the remote (e.g. github user/repo)"
                : "How should the remote change?")
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $note)
                .font(AppUI.Font.body)
                .frame(minHeight: 60, maxHeight: 100)
                .padding(AppUI.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: AppUI.Spacing.xs)
                        .stroke(Color.secondary.opacity(AppUI.Opacity.border), lineWidth: 1)
                )
                .accessibilityLabel("Remote setup instructions for the AI")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppUI.Spacing.lg)
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        guard let agent = detectedAgent else { return false }
        return agent.supportsHeadless && !projectScope.aiCommitService.isBusy
    }

    private func onAppear() {
        let detection = AIAgentDetector.detect(sessionScope: sessionScope)
        detectedAgent = detection?.agent
        detectedSessionLabel = detection?.sessionLabel
    }

    private func submit() {
        guard let agent = detectedAgent else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let userNote = trimmedNote.isEmpty ? nil : trimmedNote
        let label = detectedSessionLabel
        isPresented = false
        Task { @MainActor in
            commandRouter.showToast(
                "Configuring remote with \(agent.displayName)…", autoDismiss: .seconds(60)
            )
            let result = await projectScope.aiCommitService.setupRemote(
                note: userNote,
                projectRoot: projectRoot,
                agent: agent,
                fromSessionLabel: label
            )
            commandRouter.showToast(toastMessage(for: result), autoDismiss: .seconds(5))
            projectScope.viewModel.refresh()
        }
    }

    private func toastMessage(for result: AICommitResult) -> String {
        switch result {
        case let .success(summary): summary
        case let .failure(_, message): message
        }
    }
}
