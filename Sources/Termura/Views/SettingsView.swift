import SwiftUI

/// Main settings window with tabbed sections.
struct SettingsView: View {
    @Bindable var themeManager: ThemeManager
    @Bindable var fontSettings: FontSettings
    let themeImportService: any ThemeImportServiceProtocol
    let shellHookInstaller: any ShellHookInstallerProtocol
    let remoteControlController: RemoteControlController

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            ThemePickerView(
                themeManager: themeManager,
                themeImportService: themeImportService
            )
            .tabItem { Label("Themes", systemImage: "paintpalette") }

            FontSettingsView(fontSettings: fontSettings)
                .tabItem { Label("Fonts", systemImage: "textformat.size") }

            ShellIntegrationSettingsView(installer: shellHookInstaller)
                .tabItem { Label("Shell", systemImage: "terminal") }

            RemoteControlSettingsView(controller: remoteControlController)
                .tabItem { Label("Remote", systemImage: "iphone.gen3") }
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(SettingsWindowConfigurator())
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsView: View {
    @AppStorage(AppConfig.AgentResume.autoFillEnabledKey)
    private var autoFillEnabled: Bool = AppConfig.AgentResume.autoFillDefault

    @AppStorage(AppConfig.CostEstimation.subscriptionModeKey)
    private var subscriptionMode: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Auto-fill launch command on session restore", isOn: $autoFillEnabled)
            } header: {
                Text("Agent Resume")
            } footer: {
                Text(
                    "When enabled, reopening a project pre-fills the Composer with the previous"
                        + " session\u{2019}s agent command (e.g. \u{201C}claude\u{201D})."
                        + " Press Enter to launch or edit before confirming."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section {
                Toggle("Using subscription billing", isOn: $subscriptionMode)
            } header: {
                Text("Cost Display")
            } footer: {
                Text(
                    "Enable when using Claude Max or another subscription plan."
                        + " Hides the cost row in the Inspector \u{2014} token counts"
                        + " (Input, Output, Cache) are still shown for context window monitoring."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(AppUI.Spacing.xxl)
    }
}

// MARK: - Shell Integration Settings Tab

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

#if DEBUG
#Preview("Settings") {
    // Ephemeral defaults suite avoids touching the user's real prefs
    // from preview-only code (§3.2 — view files must not access
    // global state; an isolated preview suite keeps preview state
    // contained without persisting anything observable).
    let previewDefaults = UserDefaults(suiteName: "com.termura.preview.settings") ?? .init()
    return SettingsView(
        themeManager: ThemeManager(),
        fontSettings: FontSettings(),
        themeImportService: DebugThemeImportService(),
        shellHookInstaller: DebugShellHookInstaller(),
        remoteControlController: RemoteControlController(
            integration: NullRemoteIntegration(),
            agentBridge: NullRemoteAgentBridgeLifecycle(),
            userDefaults: previewDefaults
        )
    )
}
#endif
