import SwiftUI

/// Sheet for editing and confirming a rule draft before appending to a harness file.
struct CodifyRuleSheet: View {
    let draft: RuleDraft
    let availableFiles: [String]
    let onConfirm: (String, String) -> Void
    let onCancel: () -> Void

    @State private var editedRule: String
    @State private var selectedFile: String

    init(
        draft: RuleDraft,
        availableFiles: [String],
        onConfirm: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.availableFiles = availableFiles
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _editedRule = State(initialValue: draft.suggestedRule)
        _selectedFile = State(initialValue: availableFiles.first ?? "AGENTS.md")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xl) {
            Text("Codify Rule from Error")
                .font(.headline)

            errorContext

            Divider()

            filePicker

            ruleEditor

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Append Rule") {
                    onConfirm(selectedFile, editedRule)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editedRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppUI.Spacing.xxl)
        .frame(width: AppConfig.UI.codifyRuleSheetWidth)
        .frame(minHeight: 400)
    }

    private var errorContext: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            Text("Error")
                .sectionLabelStyle()
            Text(draft.errorSummary.title)
                .font(AppUI.Font.body)
                .foregroundColor(.red)
                .lineLimit(3)
        }
    }

    private var filePicker: some View {
        Picker("Target File", selection: $selectedFile) {
            ForEach(availableFiles, id: \.self) { file in
                Text(URL(fileURLWithPath: file).lastPathComponent).tag(file)
            }
        }
        .pickerStyle(.menu)
    }

    private var ruleEditor: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            Text("Rule (editable)")
                .sectionLabelStyle()
            TextEditor(text: $editedRule)
                .font(AppUI.Font.bodyMono)
                .frame(minHeight: 150)
                .border(Color.secondary.opacity(AppUI.Opacity.muted))
                .accessibilityLabel("Rule content")
                .accessibilityHint("Edit the rule text to be appended")
        }
    }
}
