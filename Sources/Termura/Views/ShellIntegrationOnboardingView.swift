import SwiftUI

/// Sheet shown on first launch to guide the user through shell integration installation.
/// Writes `UserDefaults` key `AppConfig.ShellIntegration.installedDefaultsKey` on success.
struct ShellIntegrationOnboardingView: View {
    @Binding var isPresented: Bool
    let installer: any ShellHookInstallerProtocol

    // MARK: - State

    @State private var selectedShell: ShellType = .zsh
    @State private var installState: InstallState = .idle
    @State private var installError: String?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xxl) {
            headerSection
            infoSection
            shellPickerSection
            actionSection
        }
        .padding(AppUI.Spacing.xxxl)
        .frame(width: AppConfig.UI.shellOnboardingSheetWidth)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
            Text("Shell Integration")
                .font(.title2.bold())
            Text("Enable smart output chunking and accurate command tracking.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
            featureRow(icon: "rectangle.split.3x1", text: "Structured output blocks per command")
            featureRow(icon: "clock", text: "Execution time and exit code per command")
            featureRow(icon: "doc.text.magnifyingglass", text: "Accurate token counting")
        }
        .padding(AppUI.Spacing.lg)
        .background(Color.accentColor.opacity(AppUI.Opacity.tint))
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.lg))
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: AppUI.Size.iconFrameLarge)
            Text(text)
                .font(.callout)
        }
    }

    // MARK: - Shell picker

    private var shellPickerSection: some View {
        Picker("Shell", selection: $selectedShell) {
            ForEach(ShellType.allCases, id: \.self) { shell in
                Text(shell.rawValue).tag(shell)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Action

    @ViewBuilder
    private var actionSection: some View {
        if let errorMsg = installError {
            Text(errorMsg)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.bottom, AppUI.Spacing.sm)
        }

        HStack {
            Button("Skip for now") {
                isPresented = false
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Spacer()

            installButton
        }
    }

    @ViewBuilder
    private var installButton: some View {
        switch installState {
        case .idle:
            Button("Install Hook") {
                performInstall()
            }
            .buttonStyle(.borderedProminent)

        case .installing:
            ProgressView()
                .controlSize(.small)

        case .done:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.callout.bold())
        }
    }

    // MARK: - Install logic

    private func performInstall() {
        installState = .installing
        installError = nil
        let shell = selectedShell

        Task {
            do {
                try await installer.install(into: shell)
                UserDefaults.standard.set(true, forKey: AppConfig.ShellIntegration.installedDefaultsKey)
                installState = .done
                try await Task.sleep(for: AppConfig.Runtime.onboardingDismissDelay)
                isPresented = false
            } catch {
                installError = error.localizedDescription
                installState = .idle
            }
        }
    }

    // MARK: - Nested types

    private enum InstallState {
        case idle, installing, done
    }
}
