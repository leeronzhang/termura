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
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)

            Divider()

            ScrollView {
                LazyVStack(spacing: DS.Spacing.xs) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, record in
                        historyRow(record, index: index)
                    }
                }
                .padding(DS.Spacing.sm)
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
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Version \(record.version)")
                        .font(DS.Font.bodyMedium)
                    Text(formattedDate(record.createdAt))
                        .font(DS.Font.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if index < history.count - 1 {
                    Button("Diff") {
                        onCompare(history[index + 1], record)
                    }
                    .font(DS.Font.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .background(selectedIndex == index ? Color.accentColor.opacity(DS.Opacity.highlight) : Color.clear)
            .cornerRadius(DS.Radius.sm)
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
