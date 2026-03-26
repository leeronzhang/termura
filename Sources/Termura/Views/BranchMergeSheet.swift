import SwiftUI

/// Sheet triggered by Cmd+M to complete a branch session.
/// Generates a summary and merges it back to the parent session's metadata layer.
struct BranchMergeSheet: View {
    let branchSession: SessionRecord
    let chunks: [OutputChunk]
    let onMerge: (String) -> Void
    let onCancel: () -> Void

    @State private var summary: String = ""
    @State private var isGenerating = false

    private let summarizer = BranchSummarizer()

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xl) {
            header
            Divider()
            branchInfo
            summaryEditor
            actionBar
        }
        .padding(AppUI.Spacing.xxl)
        .frame(width: AppConfig.UI.branchMergeSheetWidth)
        .frame(minHeight: 350)
        .onAppear { generateSummary() }
    }

    private var header: some View {
        HStack {
            Image(systemName: branchIcon)
                .foregroundColor(branchColor)
            Text("Merge Branch Summary")
                .font(.headline)
            Spacer()
        }
    }

    private var branchInfo: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            Text(branchSession.title)
                .font(AppUI.Font.title3Medium)
            HStack(spacing: AppUI.Spacing.md) {
                Text(branchSession.branchType.rawValue.capitalized)
                    .font(AppUI.Font.label)
                    .padding(.horizontal, AppUI.Spacing.md)
                    .padding(.vertical, AppUI.Spacing.xs)
                    .background(branchColor.opacity(AppUI.Opacity.selected))
                    .cornerRadius(AppUI.Radius.sm)
                Text("\(chunks.count) commands")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var summaryEditor: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            HStack {
                Text("Summary (editable)")
                    .sectionLabelStyle()
                Spacer()
                if isGenerating {
                    ProgressView().scaleEffect(AppConfig.UI.progressIndicatorScale)
                }
            }
            TextEditor(text: $summary)
                .font(AppUI.Font.bodyMono)
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(AppUI.Opacity.muted))
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Merge to Parent") {
                let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onMerge(trimmed)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func generateSummary() {
        isGenerating = true
        let capturedChunks = chunks
        let branchType = branchSession.branchType
        Task {
            let result = await summarizer.summarize(chunks: capturedChunks, branchType: branchType)
            await MainActor.run {
                summary = result
                isGenerating = false
            }
        }
    }

    private var branchIcon: String {
        switch branchSession.branchType {
        case .main: "circle.fill"
        case .investigation: "magnifyingglass"
        case .fix: "wrench.fill"
        case .review: "eye.fill"
        case .experiment: "flask.fill"
        }
    }

    private var branchColor: Color {
        switch branchSession.branchType {
        case .main: .primary
        case .investigation: .blue
        case .fix: .orange
        case .review: .green
        case .experiment: .purple
        }
    }
}
