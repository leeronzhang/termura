import SwiftUI

/// Main settings window with tabbed sections.
struct SettingsView: View {
    @Bindable var themeManager: ThemeManager
    @Bindable var fontSettings: FontSettings
    let themeImportService: any ThemeImportServiceProtocol

    var body: some View {
        TabView {
            ThemePickerView(
                themeManager: themeManager,
                themeImportService: themeImportService
            )
            .tabItem { Label("Themes", systemImage: "paintpalette") }

            FontSettingsView(fontSettings: fontSettings)
                .tabItem { Label("Fonts", systemImage: "textformat.size") }
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}

// MARK: - Font Settings Tab

struct FontSettingsView: View {
    @Bindable var fontSettings: FontSettings

    @State private var monoFamilies: [String] = []

    var body: some View {
        Form {
            terminalSection
            editorSection
            Section("Preview") {
                fontPreview
            }
        }
        .formStyle(.grouped)
        .padding(AppUI.Spacing.xxl)
        .onAppear {
            monoFamilies = FontSettings.availableMonospacedFamilies
        }
    }

    private var terminalSection: some View {
        Section("Terminal") {
            Picker("Font Family", selection: $fontSettings.terminalFontFamily) {
                Text(FontSettings.defaultFamily).tag(FontSettings.defaultFamily)
                ForEach(monoFamilies.filter { $0 != FontSettings.defaultFamily }, id: \.self) { family in
                    Text(family).tag(family)
                }
            }

            HStack {
                Text("Font Size")
                Spacer()
                Button("-") { fontSettings.zoomOut() }
                    .disabled(fontSettings.terminalFontSize <= FontSettings.minSize)
                Text("\(Int(fontSettings.terminalFontSize)) pt")
                    .frame(width: AppConfig.UI.settingsFontSizeFieldWidth, alignment: .center)
                    .monospacedDigit()
                Button("+") { fontSettings.zoomIn() }
                    .disabled(fontSettings.terminalFontSize >= FontSettings.maxSize)
                Button("Reset") { fontSettings.resetZoom() }
                    .foregroundColor(.secondary)
            }
        }
    }

    private var editorSection: some View {
        Section("Editor / Notes") {
            HStack {
                Text("Font Size")
                Spacer()
                Button("-") {
                    fontSettings.editorFontSize = max(
                        fontSettings.editorFontSize - FontSettings.zoomStep,
                        FontSettings.minSize
                    )
                }
                .disabled(fontSettings.editorFontSize <= FontSettings.minSize)
                Text("\(Int(fontSettings.editorFontSize)) pt")
                    .frame(width: AppConfig.UI.settingsFontSizeFieldWidth, alignment: .center)
                    .monospacedDigit()
                Button("+") {
                    fontSettings.editorFontSize = min(
                        fontSettings.editorFontSize + FontSettings.zoomStep,
                        FontSettings.maxSize
                    )
                }
                .disabled(fontSettings.editorFontSize >= FontSettings.maxSize)
            }
        }
    }

    private var fontPreview: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
            Text("Terminal: \(fontSettings.terminalFontFamily) \(Int(fontSettings.terminalFontSize))pt")
                .font(fontSettings.terminalSwiftUIFont())
                .foregroundColor(.primary)
            Text("Editor: \(fontSettings.terminalFontFamily) \(Int(fontSettings.editorFontSize))pt")
                .font(fontSettings.editorSwiftUIFont())
                .foregroundColor(.primary)
            Text("$ echo \"The quick brown fox jumps over the lazy dog\"")
                .font(fontSettings.terminalSwiftUIFont())
                .foregroundColor(.green)
        }
        .padding(AppUI.Spacing.lg)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
    }
}
