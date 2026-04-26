import SwiftUI

/// Scrolling list of per-file diff stats shown in `CommitPopover`. Renders
/// a "Loading…" placeholder while the numstat call is in flight, an empty
/// state when the working tree has no tracked changes, and otherwise a row
/// per file with `+added −removed` (or `bin` for binaries) plus a totals
/// summary footer.
struct CommitDiffList: View {
    let stats: [DiffStat]
    let isLoading: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
                if isLoading {
                    placeholder("Loading diff…")
                } else if stats.isEmpty {
                    placeholder("No tracked file changes")
                } else {
                    ForEach(stats) { stat in
                        diffRow(stat)
                    }
                    Divider()
                    summaryRow
                }
            }
            .padding(.horizontal, AppUI.Spacing.lg)
            .padding(.vertical, AppUI.Spacing.md)
        }
    }

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .font(AppUI.Font.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, AppUI.Spacing.sm)
    }

    private func diffRow(_ stat: DiffStat) -> some View {
        HStack(spacing: AppUI.Spacing.sm) {
            Text(stat.path)
                .font(AppUI.Font.captionMono)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if stat.isBinary {
                Text("bin")
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary)
            } else {
                if let added = stat.added, added > 0 {
                    Text("+\(added)")
                        .font(AppUI.Font.captionMono)
                        .foregroundColor(.green)
                }
                if let removed = stat.removed, removed > 0 {
                    Text("\u{2212}\(removed)")
                        .font(AppUI.Font.captionMono)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private var summaryRow: some View {
        let totalAdded = stats.compactMap(\.added).reduce(0, +)
        let totalRemoved = stats.compactMap(\.removed).reduce(0, +)
        let fileCount = stats.count
        return HStack {
            Text("\(fileCount) file\(fileCount == 1 ? "" : "s")")
                .font(AppUI.Font.captionMono)
                .foregroundColor(.secondary)
            Spacer()
            Text("+\(totalAdded) \u{2212}\(totalRemoved)")
                .font(AppUI.Font.captionMono)
                .foregroundColor(.secondary)
        }
        .padding(.top, AppUI.Spacing.xxs)
    }
}
