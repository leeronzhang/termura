import SwiftUI

/// Settings sections. Used both for the custom tab strip's enumeration
/// and for content switching. Replaces the prior native `TabView /
/// .tabItem` chrome so we can drop the rounded-square selection chip
/// the system pins behind selected items and tint only via the
/// project's brand accent (green) instead of the system blue.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case themes
    case fonts
    case shell
    case remote

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .themes: "Themes"
        case .fonts: "Fonts"
        case .shell: "Shell"
        case .remote: "Remote"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .themes: "paintpalette"
        case .fonts: "textformat.size"
        case .shell: "terminal"
        case .remote: "iphone.gen3"
        }
    }
}

/// Main settings window with tabbed sections.
struct SettingsView: View {
    @Bindable var themeManager: ThemeManager
    @Bindable var fontSettings: FontSettings
    let themeImportService: any ThemeImportServiceProtocol
    let shellHookInstaller: any ShellHookInstallerProtocol
    let remoteControlController: RemoteControlController

    @State private var selection: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider()
            selectedContent
        }
        // 16:9 aspect — 960×540 minimum, 1120×630 default open size.
        .frame(minWidth: 960, idealWidth: 1120, minHeight: 540, idealHeight: 630)
        .background(SettingsWindowConfigurator())
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        HStack(spacing: AppUI.Spacing.xxxl) {
            ForEach(SettingsTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppUI.Spacing.lg)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: AppUI.Spacing.sm) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .frame(height: 26)
                Text(tab.label)
                    .font(AppUI.Font.label)
            }
            .foregroundStyle(selection == tab ? Color.brandGreen : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }

    // MARK: - Content switch

    @ViewBuilder
    private var selectedContent: some View {
        switch selection {
        case .general:
            GeneralSettingsView()
        case .themes:
            ThemePickerView(
                themeManager: themeManager,
                themeImportService: themeImportService
            )
        case .fonts:
            FontSettingsView(fontSettings: fontSettings)
        case .shell:
            ShellIntegrationSettingsView(installer: shellHookInstaller)
        case .remote:
            RemoteControlSettingsView(controller: remoteControlController)
        }
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
