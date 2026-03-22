import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings panel for browsing built-in themes and importing custom ones.
struct ThemePickerView: View {
    @ObservedObject var themeManager: ThemeManager
    let themeImportService: any ThemeImportServiceProtocol

    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            Text("Themes")
                .font(DS.Font.title1)

            themeGrid

            importSection

            if let error = importError {
                Text(error)
                    .font(DS.Font.body)
                    .foregroundColor(.red)
            }
        }
        .padding(DS.Spacing.xxl)
        .frame(minWidth: 480)
    }

    // MARK: - Theme Grid

    private var themeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: DS.Spacing.lg) {
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
                .font(DS.Font.title3Medium)
            Spacer()
            Button("Import Theme…") { openImportPanel() }
        }
        .padding(.top, DS.Spacing.md)
    }

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        panel.message = "Select a .json or .itermcolors theme file"
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importTheme(from: url)
    }

    private func importTheme(from url: URL) {
        let service = themeImportService
        Task { @MainActor in
            do {
                let definition: ThemeDefinition
                if url.pathExtension.lowercased() == "itermcolors" {
                    definition = try await service.importItermColors(from: url)
                } else {
                    definition = try await service.importJSON(from: url)
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
        VStack(spacing: DS.Spacing.md) {
            colorSwatches
            Text(definition.name)
                .font(DS.Font.label)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(isSelected
                    ? Color.accentColor.opacity(DS.Opacity.selected)
                    : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(
                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: 1
                )
        )
        .onTapGesture { onSelect() }
    }

    private var colorSwatches: some View {
        let keys = ["ansiBlack", "ansiRed", "ansiGreen", "ansiYellow",
                    "ansiBlue", "ansiMagenta", "ansiCyan", "ansiWhite"]
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(14)), count: 4), spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Rectangle()
                    .fill(ThemeDefinition.color(fromHex: definition.colors[key]) ?? .gray)
                    .frame(width: 14, height: 14)
                    .cornerRadius(DS.Radius.xs)
            }
        }
    }
}
