import SwiftUI

/// Side-by-side diff view for comparing two versions of a rule file.
struct RuleDiffView: View {
    let oldVersion: RuleFileRecord
    let newVersion: RuleFileRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HSplitView {
                diffPane(title: "v\(oldVersion.version)", content: oldVersion.content, isOld: true)
                diffPane(title: "v\(newVersion.version)", content: newVersion.content, isOld: false)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var header: some View {
        HStack {
            Text(newVersion.fileName)
                .font(.headline)
            Spacer()
            Text("v\(oldVersion.version) → v\(newVersion.version)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(AppUI.Spacing.lg)
    }

    private func diffPane(title: String, content: String, isOld: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppUI.Font.panelHeader)
                .foregroundColor(isOld ? .red : .green)
                .padding(.horizontal, AppUI.Spacing.md)
                .padding(.vertical, AppUI.Spacing.sm)
            Divider()
            ScrollView {
                Text(content)
                    .font(AppUI.Font.bodyMono)
                    .textSelection(.enabled)
                    .padding(AppUI.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
