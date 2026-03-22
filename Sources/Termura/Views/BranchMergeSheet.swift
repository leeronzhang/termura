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
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            header
            Divider()
            branchInfo
            summaryEditor
            actionBar
        }
        .padding(DS.Spacing.xxl)
        .frame(width: 480)
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
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(branchSession.title)
                .font(DS.Font.title3Medium)
            HStack(spacing: DS.Spacing.md) {
                Text(branchSession.branchType.rawValue.capitalized)
                    .font(DS.Font.label)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(branchColor.opacity(DS.Opacity.selected))
                    .cornerRadius(DS.Radius.sm)
                Text("\(chunks.count) commands")
                    .font(DS.Font.label)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var summaryEditor: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("Summary (editable)")
                    .sectionLabelStyle()
                Spacer()
                if isGenerating {
                    ProgressView().scaleEffect(0.6)
                }
            }
            TextEditor(text: $summary)
                .font(DS.Font.bodyMono)
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(DS.Opacity.muted))
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
        case .main: return "circle.fill"
        case .investigation: return "magnifyingglass"
        case .fix: return "wrench.fill"
        case .review: return "eye.fill"
        case .experiment: return "flask.fill"
        }
    }

    private var branchColor: Color {
        switch branchSession.branchType {
        case .main: return .primary
        case .investigation: return .blue
        case .fix: return .orange
        case .review: return .green
        case .experiment: return .purple
        }
    }
}
