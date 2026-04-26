import SwiftUI

/// Timeline view showing version history of a rule file.
struct RuleHistoryView: View {
    let history: [RuleFileRecord]
    let onSelectVersion: (RuleFileRecord) -> Void
    let onCompare: (RuleFileRecord, RuleFileRecord) -> Void

    @State private var selectedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Version History")
                .panelHeaderStyle()
                .padding(.horizontal, AppUI.Spacing.lg)
                .padding(.vertical, AppUI.Spacing.md)

            Divider()

            ScrollView {
                LazyVStack(spacing: AppUI.Spacing.xs) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, record in
                        historyRow(record, index: index)
                    }
                }
                .padding(AppUI.Spacing.sm)
            }
        }
        .frame(minWidth: 200)
    }

    private func historyRow(_ record: RuleFileRecord, index: Int) -> some View {
        Button {
            selectedIndex = index
            onSelectVersion(record)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                    Text("Version \(record.version)")
                        .font(AppUI.Font.bodyMedium)
                    Text(formattedDate(record.createdAt))
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if index < history.count - 1 {
                    Button("Diff") {
                        onCompare(history[index + 1], record)
                    }
                    .font(AppUI.Font.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.brandGreen)
                }
            }
            .padding(.horizontal, AppUI.Spacing.md)
            .padding(.vertical, AppUI.Spacing.md)
            .background(selectedIndex == index ? Color.brandGreen.opacity(AppUI.Opacity.highlight) : Color.clear)
            .cornerRadius(AppUI.Radius.sm)
        }
        .buttonStyle(.plain)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
