import SwiftUI

// MARK: - Problems Section

/// Collapsible diagnostics section rendered inside SidebarProjectContent.
/// Appears when DiagnosticsStore has items; stays hidden otherwise.
struct ProblemsSection: View {
    var diagnosticsStore: DiagnosticsStore
    var onOpenFile: ((String, FileOpenMode) -> Void)?

    var body: some View {
        if diagnosticsStore.hasProblems {
            VStack(alignment: .leading, spacing: 0) {
                problemsHeader
                problemsList
            }
        }
    }

    // MARK: - Header

    private var problemsHeader: some View {
        HStack {
            Text("Problems")
                .panelHeaderStyle()
            Spacer()
            countSummary
            Button {
                diagnosticsStore.clearAll()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear all problems")
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    @ViewBuilder
    private var countSummary: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            if diagnosticsStore.errorCount > 0 {
                Label("\(diagnosticsStore.errorCount)", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(AppUI.Font.captionMono.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            if diagnosticsStore.warningCount > 0 {
                Label(
                    "\(diagnosticsStore.warningCount)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundColor(.orange)
                .font(AppUI.Font.captionMono.weight(.semibold))
                .labelStyle(.titleAndIcon)
            }
        }
    }

    // MARK: - List

    private var problemsList: some View {
        VStack(spacing: 0) {
            ForEach(diagnosticsStore.items) { item in
                ProblemRowView(item: item) {
                    onOpenFile?(item.file, .edit)
                }
            }
        }
    }
}

// MARK: - Problem Row

struct ProblemRowView: View {
    let item: DiagnosticItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppUI.Spacing.smMd) {
                severityIcon
                VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
                    Text(item.locationLabel)
                        .font(AppUI.Font.labelMono)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(item.message)
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppUI.Spacing.xxxl)
            .padding(.vertical, AppUI.Spacing.smMd)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var severityIcon: some View {
        switch item.severity {
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(AppUI.Font.label)
                .frame(width: 16)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(AppUI.Font.label)
                .frame(width: 16)
        case .note:
            Image(systemName: "info.circle.fill")
                .foregroundColor(.secondary)
                .font(AppUI.Font.label)
                .frame(width: 16)
        }
    }
}
