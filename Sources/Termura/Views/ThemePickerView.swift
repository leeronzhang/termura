import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings panel for browsing built-in themes and importing custom ones.
struct ThemePickerView: View {
    @Bindable var themeManager: ThemeManager
    let themeImportService: any ThemeImportServiceProtocol

    @State private var importError: String?

    var body: some View {
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
        .padding(AppUI.Spacing.xxl)
        .frame(minWidth: 480)
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
                    ? Color.accentColor.opacity(AppUI.Opacity.selected)
                    : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppUI.Radius.lg)
                .stroke(
                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: 1
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
        themeImportService: MockThemeImportService()
    )
}
#endif
