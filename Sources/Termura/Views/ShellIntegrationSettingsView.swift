import SwiftUI

/// Settings tab for installing the OSC 133 shell hook into the user's RC file.
struct ShellIntegrationSettingsView: View {
    @Environment(\.userDefaults) private var userDefaults
    @State private var selectedShell: ShellType = .zsh
    @State private var installState: InstallState = .idle
    @State private var installError: String?
    @State private var isInstalledZsh = false
    @State private var isInstalledBash = false

    let installer: any ShellHookInstallerProtocol

    var body: some View {
        Form {
            statusSection
            installSection
        }
        .formStyle(.grouped)
        .padding(AppUI.Spacing.xxl)
        .task { await refreshStatus() }
    }

    private var statusSection: some View {
        Section("Status") {
            statusRow(shell: .zsh, installed: isInstalledZsh)
            statusRow(shell: .bash, installed: isInstalledBash)
        }
    }

    private func statusRow(shell: ShellType, installed: Bool) -> some View {
        HStack {
            Text(shell.rawValue)
                .font(AppUI.Font.body)
            Spacer()
            if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.callout)
            } else {
                Text("Not installed")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shell.rawValue) shell integration: \(installed ? "Installed" : "Not installed")")
    }

    private var installSection: some View {
        Section {
            VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
                featureRow(icon: "rectangle.split.3x1", text: "Structured output blocks per command")
                featureRow(icon: "clock", text: "Execution time and exit code per command")
                featureRow(icon: "doc.text.magnifyingglass", text: "Accurate token counting")
            }
            .padding(.vertical, AppUI.Spacing.sm)

            Picker("Shell", selection: $selectedShell) {
                ForEach(ShellType.allCases, id: \.self) { shell in
                    Text(shell.rawValue).tag(shell)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let errorMsg = installError {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                installButton
            }
        } header: {
            Text("Install Hook")
        } footer: {
            Text("Appends a small OSC 133 script to your shell RC file (\(selectedShell.rcFileName)). No data leaves your machine.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var installButton: some View {
        switch installState {
        case .idle:
            Button("Install Hook") { performInstall() }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Install shell integration hook for \(selectedShell.rawValue)")
        case .installing:
            ProgressView().controlSize(.small)
                .accessibilityLabel("Installing shell hook")
        case .done:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.callout.bold())
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(.brandGreen)
                .frame(width: AppUI.Size.iconFrameLarge)
                .accessibilityHidden(true)
            Text(text).font(.callout)
        }
    }

    private func performInstall() {
        installState = .installing
        installError = nil
        let shell = selectedShell
        Task {
            do {
                try await installer.install(into: shell)
                userDefaults.set(true, forKey: AppConfig.ShellIntegration.installedDefaultsKey)
                await refreshStatus()
                installState = .done
                try await Task.sleep(for: AppConfig.Runtime.onboardingDismissDelay)
                installState = .idle
            } catch {
                installError = error.localizedDescription
                installState = .idle
            }
        }
    }

    private func refreshStatus() async {
        isInstalledZsh = await installer.isInstalled(for: .zsh)
        isInstalledBash = await installer.isInstalled(for: .bash)
    }

    private enum InstallState { case idle, installing, done }
}
