import SwiftUI

/// Sidebar panel for browsing and managing harness rule files.
struct HarnessSidebarView: View {
    @ObservedObject var viewModel: HarnessViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            fileList
            Divider()
            if !viewModel.corruptionResults.isEmpty {
                corruptionSection
                Divider()
            }
            footer
        }
        .frame(minWidth: 260, maxWidth: 320)
        .background(.ultraThinMaterial)
        .onAppear { Task { await viewModel.loadRuleFiles() } }
    }

    private var header: some View {
        HStack {
            Text("Harness Rules")
                .panelHeaderStyle()
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark").font(AppUI.Font.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
    }

    private var fileList: some View {
        List(viewModel.ruleFiles) { file in
            Button {
                Task { await viewModel.selectFile(file.filePath) }
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                    Text(file.fileName)
                        .font(AppUI.Font.body)
                    Spacer()
                    Text("v\(file.version)")
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.sidebar)
    }

    private var corruptionSection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            Text("Issues (\(viewModel.corruptionResults.count))")
                .font(AppUI.Font.sectionHeader)
                .foregroundColor(.orange)
                .padding(.horizontal, AppUI.Spacing.lg)
                .padding(.top, AppUI.Spacing.md)

            ForEach(viewModel.corruptionResults) { result in
                HStack(spacing: AppUI.Spacing.md) {
                    Image(systemName: severityIcon(result.severity))
                        .foregroundColor(severityColor(result.severity))
                        .font(AppUI.Font.caption)
                    Text(result.message)
                        .font(AppUI.Font.label)
                        .lineLimit(2)
                }
                .padding(.horizontal, AppUI.Spacing.lg)
                .padding(.vertical, AppUI.Spacing.xs)
            }
        }
        .padding(.bottom, AppUI.Spacing.md)
    }

    private var footer: some View {
        HStack {
            Button("Scan") {
                Task { await viewModel.runCorruptionScan() }
            }
            .disabled(viewModel.selectedFilePath == nil || viewModel.isScanning)
            .font(AppUI.Font.label)
            Spacer()
        }
        .padding(AppUI.Spacing.md)
    }

    private func severityIcon(_ severity: CorruptionSeverity) -> String {
        switch severity {
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func severityColor(_ severity: CorruptionSeverity) -> Color {
        switch severity {
        case .error: .red
        case .warning: .orange
        case .info: .blue
        }
    }
}
