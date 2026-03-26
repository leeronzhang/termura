import SwiftUI

/// Floating toolbar for pausing/resuming agent execution and inserting directives.
/// Shown when an agent is actively running.
struct InterventionToolbarView: View {
    let agentType: AgentType
    let status: AgentStatus
    let onPause: () -> Void
    let onResume: () -> Void
    let onInsertDirective: (String) -> Void

    @State private var showDirectiveInput = false
    @State private var directiveText = ""

    var body: some View {
        HStack(spacing: AppUI.Spacing.md) {
            agentLabel

            Divider().frame(height: AppUI.Size.toolbarDivider)

            if status == .thinking || status == .toolRunning {
                pauseButton
            } else if status == .idle {
                resumeButton
            }

            insertButton
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.smMd)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppUI.Radius.lg)
                .stroke(Color.secondary.opacity(AppUI.Opacity.softBorder), lineWidth: 0.5)
        )
        .popover(isPresented: $showDirectiveInput) {
            directivePopover
        }
    }

    private var agentLabel: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            AgentStatusBadgeView(status: status, agentType: agentType)
            Text(agentType.rawValue)
                .font(AppUI.Font.labelMedium)
        }
    }

    private var pauseButton: some View {
        Button(action: onPause) {
            Image(systemName: "pause.fill")
                .font(AppUI.Font.body)
        }
        .buttonStyle(.plain)
        .help("Pause agent (Ctrl+C)")
    }

    private var resumeButton: some View {
        Button(action: onResume) {
            Image(systemName: "play.fill")
                .font(AppUI.Font.body)
        }
        .buttonStyle(.plain)
        .help("Resume agent")
    }

    private var insertButton: some View {
        Button {
            showDirectiveInput.toggle()
        } label: {
            Image(systemName: "text.insert")
                .font(AppUI.Font.body)
        }
        .buttonStyle(.plain)
        .help("Insert directive")
    }

    private var directivePopover: some View {
        VStack(spacing: AppUI.Spacing.md) {
            Text("Insert Directive")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Type instruction\u{2026}", text: $directiveText)
                .textFieldStyle(.roundedBorder)
                .frame(width: AppConfig.UI.fieldPickerWidth)
                .onSubmit {
                    let text = directiveText.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    onInsertDirective(text)
                    directiveText = ""
                    showDirectiveInput = false
                }
        }
        .padding(AppUI.Spacing.lg)
    }
}
