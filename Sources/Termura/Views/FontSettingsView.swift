import SwiftUI

/// Settings tab for configuring terminal and editor font family and size.
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
                Button("-") {
                    fontSettings.terminalFontSize = max(
                        fontSettings.terminalFontSize - FontSettings.zoomStep,
                        FontSettings.minSize
                    )
                }
                .disabled(fontSettings.terminalFontSize <= FontSettings.minSize)
                .accessibilityLabel("Decrease terminal font size")
                Text("\(Int(fontSettings.terminalFontSize)) pt")
                    .frame(width: AppConfig.UI.settingsFontSizeFieldWidth, alignment: .center)
                    .monospacedDigit()
                Button("+") {
                    fontSettings.terminalFontSize = min(
                        fontSettings.terminalFontSize + FontSettings.zoomStep,
                        FontSettings.maxSize
                    )
                }
                .disabled(fontSettings.terminalFontSize >= FontSettings.maxSize)
                .accessibilityLabel("Increase terminal font size")
                Button("Reset") {
                    fontSettings.terminalFontSize = FontSettings.defaultTerminalSize
                }
                .foregroundColor(.secondary)
                .accessibilityLabel("Reset terminal font size")
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
                .accessibilityLabel("Decrease editor font size")
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
                .accessibilityLabel("Increase editor font size")
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

#if DEBUG
#Preview("Font Settings") {
    FontSettingsView(fontSettings: FontSettings())
        .frame(width: 520)
}
#endif
