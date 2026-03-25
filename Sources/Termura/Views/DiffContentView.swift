import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "DiffContentView")

/// Renders a git diff for a single file in the main content area.
struct DiffContentView: View {
    let filePath: String
    let isStaged: Bool
    let isUntracked: Bool
    let gitService: any GitServiceProtocol
    let projectRoot: String

    @State private var diffText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadDiff() }
    }

    // MARK: - Header helpers

    private var headerIcon: String {
        if isUntracked { return "questionmark.circle" }
        return isStaged ? "circle.fill" : "pencil.circle.fill"
    }

    private var headerColor: Color {
        if isUntracked { return .secondary }
        return isStaged ? .green : .orange
    }

    private var headerBadge: String {
        if isUntracked { return "Untracked" }
        return isStaged ? "Staged" : "Working Tree"
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: headerIcon)
                .foregroundColor(headerColor)
                .font(AppUI.Font.label)
            Text(filePath)
                .font(AppUI.Font.labelMono)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Text(headerBadge)
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, AppUI.Spacing.md)
                .padding(.vertical, AppUI.Spacing.xs)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(AppUI.Opacity.selected))
                )
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            VStack(spacing: AppUI.Spacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(AppUI.Font.hero)
                    .foregroundColor(.secondary)
                Text(error)
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if diffText.isEmpty {
            VStack(spacing: AppUI.Spacing.md) {
                Image(systemName: "checkmark.circle")
                    .font(AppUI.Font.hero)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
                Text("No changes")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            diffView
        }
    }

    private var diffView: some View {
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                    diffLineView(line)
                }
            }
            .padding(AppUI.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }

    // MARK: - Diff line rendering

    private var diffLines: [DiffLine] {
        diffText.components(separatedBy: "\n").map { DiffLine(raw: $0) }
    }

    private func diffLineView(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            Text(line.raw)
                .font(AppUI.Font.bodyMono)
                .foregroundColor(line.foregroundColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppUI.Spacing.md)
        .padding(.vertical, 1)
        .background(line.backgroundColor)
    }

    // MARK: - Data loading

    private func loadDiff() async {
        do {
            if isUntracked {
                // Untracked files have no diff — show full content with + prefix
                let url = URL(fileURLWithPath: projectRoot)
                    .appendingPathComponent(filePath)
                let content: String = try await Task.detached {
                    try String(contentsOf: url, encoding: .utf8)
                }.value
                diffText = content.components(separatedBy: "\n")
                    .map { "+\($0)" }
                    .joined(separator: "\n")
            } else {
                diffText = try await gitService.diff(
                    file: filePath,
                    staged: isStaged,
                    at: projectRoot
                )
            }
        } catch {
            logger.warning("Failed to load diff for \(filePath): \(error.localizedDescription)")
            errorMessage = "Failed to load diff"
        }
        isLoading = false
    }
}

// MARK: - Diff line model

private struct DiffLine {
    let raw: String

    var foregroundColor: Color {
        if raw.hasPrefix("+++") || raw.hasPrefix("---") { return .secondary }
        if raw.hasPrefix("+") { return Color(.systemGreen) }
        if raw.hasPrefix("-") { return Color(.systemRed) }
        if raw.hasPrefix("@@") { return Color(.systemCyan) }
        return .primary
    }

    var backgroundColor: Color {
        if raw.hasPrefix("+") && !raw.hasPrefix("+++") {
            return Color.green.opacity(0.1)
        }
        if raw.hasPrefix("-") && !raw.hasPrefix("---") {
            return Color.red.opacity(0.1)
        }
        return .clear
    }
}
