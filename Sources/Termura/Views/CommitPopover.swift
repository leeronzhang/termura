import Foundation
import OSLog
import SwiftUI

private let popoverLogger = Logger(subsystem: "com.termura.app", category: "CommitPopover")

/// Anchored popover from the sidebar [Commit] button. Shows the change set,
/// lets the user add an optional context note, and dispatches the commit to
/// the headless CLI agent via `AICommitService`. Result feedback flows through
/// `commandRouter.showToast` after the popover closes.
struct CommitPopover: View {
    @Environment(\.commandRouter) private var commandRouter
    @Environment(\.sessionScope) private var sessionScope
    @Environment(\.projectScope) private var projectScope

    @Binding var isPresented: Bool
    let projectRoot: URL

    @State private var note: String = ""
    @State private var diffStats: [DiffStat] = []
    @State private var isLoadingStats = true

    /// Resolved when the view appears; cached so toggling note text doesn't re-detect.
    @State private var detectedAgent: AgentType?
    @State private var detectedSessionLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AICommitPopoverHeader(agent: detectedAgent, sessionLabel: detectedSessionLabel)
            Divider()
            CommitDiffList(stats: diffStats, isLoading: isLoadingStats)
                .frame(minHeight: 120, maxHeight: 240)
            Divider()
            noteSection
            Divider()
            footer
        }
        .frame(width: 420)
        .frame(maxHeight: 520)
        .onAppear { onAppear() }
    }

    // MARK: - Sections

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
            Text("Notes for the AI (optional)")
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $note)
                .font(AppUI.Font.body)
                .frame(minHeight: 60, maxHeight: 100)
                .padding(AppUI.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: AppUI.Radius.sm)
                        .stroke(Color.secondary.opacity(AppUI.Opacity.border), lineWidth: 1)
                )
                .accessibilityLabel("Optional note for the AI commit")
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.escape)
            Button(action: submit) {
                Text("Commit")
                    .padding(.horizontal, AppUI.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
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
        Task { await loadStats() }
    }

    private func loadStats() async {
        defer { isLoadingStats = false }
        do {
            diffStats = try await projectScope.gitService.numstat(at: projectRoot.path)
        } catch {
            popoverLogger.warning("numstat failed: \(error.localizedDescription, privacy: .public)")
            diffStats = []
        }
    }

    private func submit() {
        guard let agent = detectedAgent else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let userNote = trimmedNote.isEmpty ? nil : trimmedNote
        let label = detectedSessionLabel
        isPresented = false
        Task { @MainActor in
            commandRouter.showToast("Committing with \(agent.displayName)…", autoDismiss: .seconds(60))
            let result = await projectScope.aiCommitService.commit(
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
        case let .success(subject): "Committed: \(subject)"
        case let .failure(_, message): message
        }
    }
}
