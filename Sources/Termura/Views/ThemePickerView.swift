import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings panel for browsing built-in themes and importing custom ones.
struct ThemePickerView: View {
    @Bindable var themeManager: ThemeManager
    let themeImportService: any ThemeImportServiceProtocol

    @State private var importError: String?

    var body: some View {
        // Wrap the column in a top-leading frame so the content sits
        // directly under the Settings tab strip instead of being
        // vertically centered. The other tabs achieve this implicitly
        // (FontSettingsView uses `Form` which fills, AISettingsView
        // uses an explicit `maxHeight: .infinity`); without this frame
        // ThemePickerView's intrinsic ~400pt height left big empty
        // bands above and below in the 540pt-min Settings window.
        ScrollView {
            VStack(alignment: .leading, spacing: AppUI.Spacing.xl) {
                Text("Themes")
                    .font(AppUI.Font.title1)

                themeGrid

                importSection

                if let error = importError {
                    Text(error)
                        .font(AppUI.Font.body)
                        .foregroundColor(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(AppUI.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Theme Grid

    private var themeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: AppUI.Spacing.lg) {
            ForEach(themeManager.availableDefinitions) { definition in
                ThemeCard(
                    definition: definition,
                    isSelected: themeManager.selectedThemeID == definition.id
                ) {
                    themeManager.apply(definition: definition)
                }
            }
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        HStack {
            Text("Custom Themes")
                .font(AppUI.Font.title3Medium)
            Spacer()
            Button("Import Theme\u{2026}") { openImportPanel() }
        }
        .padding(.top, AppUI.Spacing.md)
    }

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        panel.message = String(localized: "Select a .json or .itermcolors theme file")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importTheme(from: url)
    }

    private func importTheme(from url: URL) {
        let service = themeImportService
        Task { @MainActor in
            do {
                let definition: ThemeDefinition = if url.pathExtension.lowercased() == "itermcolors" {
                    try await service.importItermColors(from: url)
                } else {
                    try await service.importJSON(from: url)
                }
                themeManager.addCustomTheme(definition)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let definition: ThemeDefinition
    let isSelected: Bool
    let onSelect: () -> Void

    /// Accent color for the selected-card highlight. Reads the
    /// theme's own `statusInfo` (or falls back through `cursor` →
    /// `keyword` → the global brand accent) so each card lights up
    /// in a hue that belongs to its palette — instead of pasting the
    /// same green `brandGreen` over every theme, which looked
    /// patched-on against Gruvbox/Solarized/Monokai swatches.
    private var themeAccent: SwiftUI.Color {
        ThemeDefinition.color(fromHex: definition.colors["statusInfo"])
            ?? ThemeDefinition.color(fromHex: definition.colors["cursor"])
            ?? ThemeDefinition.color(fromHex: definition.colors["keyword"])
            ?? .brandGreen
    }

    var body: some View {
        VStack(spacing: AppUI.Spacing.md) {
            colorSwatches
            Text(definition.name)
                .font(AppUI.Font.label)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(AppUI.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppUI.Radius.lg)
                .fill(isSelected
                    ? themeAccent.opacity(AppUI.Opacity.selected)
                    : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppUI.Radius.lg)
                .stroke(
                    isSelected ? themeAccent : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .onTapGesture { onSelect() }
        .accessibilityLabel(definition.name)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(.default) { onSelect() }
    }

    private var colorSwatches: some View {
        let keys = ["ansiBlack", "ansiRed", "ansiGreen", "ansiYellow",
                    "ansiBlue", "ansiMagenta", "ansiCyan", "ansiWhite"]
        let cols = Array(repeating: GridItem(.fixed(AppUI.Size.themeCheckbox)), count: AppConfig.UI.themeGridColumns)
        return LazyVGrid(columns: cols, spacing: AppUI.Spacing.xxs) {
            ForEach(keys, id: \.self) { key in
                Rectangle()
                    .fill(ThemeDefinition.color(fromHex: definition.colors[key]) ?? .gray)
                    .frame(width: AppUI.Size.themeCheckbox, height: AppUI.Size.themeCheckbox)
                    .cornerRadius(AppUI.Radius.xs)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Theme Picker") {
    ThemePickerView(
        themeManager: ThemeManager(),
        themeImportService: DebugThemeImportService()
    )
}
#endif
