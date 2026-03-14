import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings panel for browsing built-in themes and importing custom ones.
struct ThemePickerView: View {
    @ObservedObject var themeManager: ThemeManager
    let themeImportService: any ThemeImportServiceProtocol

    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Themes")
                .font(.system(size: 16, weight: .semibold))

            themeGrid

            importSection

            if let error = importError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 480)
    }

    // MARK: - Theme Grid

    private var themeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
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
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button("Import Theme…") { openImportPanel() }
        }
        .padding(.top, 8)
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
        VStack(spacing: 6) {
            colorSwatches
            Text(definition.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                    ? Color.accentColor.opacity(0.15)
                    : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
                    .cornerRadius(2)
            }
        }
    }
}
