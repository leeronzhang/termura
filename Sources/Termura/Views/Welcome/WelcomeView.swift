import SwiftUI

/// Cold-launch onboarding surface. Two-column layout: primary actions
/// on the left (logo + buttons + show-on-launch toggle), recents on
/// the right. State-free — all behaviour goes through `WelcomeViewModel`.
struct WelcomeView: View {
    @Bindable var viewModel: WelcomeViewModel

    var body: some View {
        HStack(spacing: 0) {
            actionsColumn
            Divider()
            recentsColumn
        }
        .frame(width: AppConfig.UI.welcomeWindowWidth,
               height: AppConfig.UI.welcomeWindowHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Actions column (left)

    private var actionsColumn: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xl) {
            heroHeader
            Spacer(minLength: 0)
            actionButtons
            Spacer(minLength: 0)
            showAtStartupToggle
        }
        .padding(AppUI.Spacing.xxxl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroHeader: some View {
        HStack(alignment: .top, spacing: AppUI.Spacing.sm) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: AppConfig.UI.welcomeLogoHeight)
                .accessibilityLabel(Text("Termura"))
            Text(verbatim: "v\(viewModel.appVersion)")
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary)
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
            newProjectButton
            openExistingButton
        }
    }

    private var showAtStartupToggle: some View {
        Toggle("Show this window on launch", isOn: $viewModel.showAtStartup)
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("welcomeShowAtStartupToggle")
    }

    private var newProjectButton: some View {
        Button {
            viewModel.createNewProject()
        } label: {
            Text("New Project…")
                .font(AppUI.Font.title2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppUI.Spacing.md)
        }
        .buttonStyle(.borderedProminent)
        .tint(.brandGreen)
        .controlSize(.large)
        .keyboardShortcut("n", modifiers: [.command])
        .accessibilityIdentifier("welcomeNewProjectButton")
    }

    private var openExistingButton: some View {
        Button {
            viewModel.openExistingProject()
        } label: {
            Text("Open Existing Project…")
                .font(AppUI.Font.title2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppUI.Spacing.md)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .keyboardShortcut("o", modifiers: [.command])
        .accessibilityIdentifier("welcomeOpenProjectButton")
    }

    // MARK: - Recents column (right)

    private var recentsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            recentsHeader
            if viewModel.recents.isEmpty {
                recentsEmptyState
            } else {
                recentsList
            }
        }
        .frame(width: AppConfig.UI.welcomeRecentsColumnWidth)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var recentsHeader: some View {
        Text("Recent Projects")
            .font(AppUI.Font.sectionHeader)
            .textCase(.uppercase)
            .foregroundColor(.secondary)
            .padding(.horizontal, AppUI.Spacing.xl)
            .padding(.top, AppUI.Spacing.xl)
            .padding(.bottom, AppUI.Spacing.md)
    }

    private var recentsEmptyState: some View {
        VStack(spacing: AppUI.Spacing.md) {
            Spacer(minLength: 0)
            Image(systemName: "tray")
                .font(AppUI.Font.hero)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
                .accessibilityHidden(true)
            Text("No recent projects")
                .font(AppUI.Font.body)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.recents, id: \.path) { project in
                    WelcomeRecentRow(project: project,
                                     onOpen: { viewModel.openRecent(project) },
                                     onRemove: { viewModel.removeRecent(project) })
                    Divider().opacity(AppUI.Opacity.softBorder)
                }
            }
        }
    }
}
