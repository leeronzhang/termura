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
        HStack(spacing: DS.Spacing.md) {
            agentLabel

            Divider().frame(height: DS.Size.toolbarDivider)

            if status == .thinking || status == .toolRunning {
                pauseButton
            } else if status == .idle {
                resumeButton
            }

            insertButton
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.smMd)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(Color.secondary.opacity(DS.Opacity.softBorder), lineWidth: 0.5)
        )
        .popover(isPresented: $showDirectiveInput) {
            directivePopover
        }
    }

    private var agentLabel: some View {
        HStack(spacing: DS.Spacing.sm) {
            AgentStatusBadgeView(status: status, agentType: agentType)
            Text(agentType.rawValue)
                .font(DS.Font.labelMedium)
        }
    }

    private var pauseButton: some View {
        Button(action: onPause) {
            Image(systemName: "pause.fill")
                .font(DS.Font.body)
        }
        .buttonStyle(.plain)
        .help("Pause agent (Ctrl+C)")
    }

    private var resumeButton: some View {
        Button(action: onResume) {
            Image(systemName: "play.fill")
                .font(DS.Font.body)
        }
        .buttonStyle(.plain)
        .help("Resume agent")
    }

    private var insertButton: some View {
        Button {
            showDirectiveInput.toggle()
        } label: {
            Image(systemName: "text.insert")
                .font(DS.Font.body)
        }
        .buttonStyle(.plain)
        .help("Insert directive")
    }

    private var directivePopover: some View {
        VStack(spacing: DS.Spacing.md) {
            Text("Insert Directive")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Type instruction\u{2026}", text: $directiveText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit {
                    let text = directiveText.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    onInsertDirective(text)
                    directiveText = ""
                    showDirectiveInput = false
                }
        }
        .padding(DS.Spacing.lg)
    }
}
