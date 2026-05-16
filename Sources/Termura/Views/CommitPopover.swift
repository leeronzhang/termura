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

    /// PATH-fallback agent resolved asynchronously when no session matched.
    /// nil until probed, or permanently nil when no headless CLI is on PATH.
    @State private var pathProbedAgent: AgentType?
    @State private var hasProbed = false

    /// Live, session-derived detection. Recomputed on every body invocation so
    /// opening a new agent session while the popover is visible updates the
    /// primary button without requiring a popover reopen.
    private var sessionDetection: AIAgentDetection? {
        AIAgentDetector.detect(sessionScope: sessionScope)
    }

    private var effectiveDetection: AIAgentDetection? {
        if let live = sessionDetection { return live }
        if let probed = pathProbedAgent {
            return AIAgentDetection(agent: probed, sessionLabel: nil)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
            AICommitPopoverHeader(
                agent: effectiveDetection?.agent,
                sessionLabel: effectiveDetection?.sessionLabel
            )
            CommitDiffList(stats: diffStats, isLoading: isLoadingStats)
                .frame(minHeight: 120, maxHeight: 240)
                .padding(.horizontal, AppUI.Spacing.lg)
            noteSection
            AICommitPopoverFooter(
                primaryLabel: "Commit",
                primaryEnabled: canSubmit,
                onCancel: { isPresented = false },
                onPrimary: submit
            )
        }
        .frame(width: 420)
        .frame(maxHeight: 520)
        .padding(.vertical, AppUI.Spacing.xs)
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
                    RoundedRectangle(cornerRadius: AppUI.Spacing.xs)
                        .stroke(Color.secondary.opacity(AppUI.Opacity.border), lineWidth: 1)
                )
                .accessibilityLabel("Optional note for the AI commit")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppUI.Spacing.lg)
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        guard let agent = effectiveDetection?.agent else { return false }
        return agent.supportsHeadless && !projectScope.aiCommitService.isBusy
    }

    private func onAppear() {
        // WHY: stats + PATH probe are independent reads kicked off on view appear; bundled
        // into one Task so SwiftLint's consecutive-fire-and-forget guard stays happy and
        // we only allocate a single Task per popover open.
        // OWNER: CommitPopover — self-completing, no cancellation needed (cheap reads).
        // TEARDOWN: completes when both awaits return; view-scoped lifetime is sufficient.
        Task {
            await loadStats()
            await probeAgentIfNeeded()
        }
    }

    private func probeAgentIfNeeded() async {
        guard sessionDetection == nil, !hasProbed else { return }
        hasProbed = true
        pathProbedAgent = await projectScope.aiCommitService.probeAvailableHeadlessAgent()
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
        guard let detection = effectiveDetection else { return }
        let agent = detection.agent
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let userNote = trimmedNote.isEmpty ? nil : trimmedNote
        let label = detection.sessionLabel
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
