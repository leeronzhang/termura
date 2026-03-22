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
                Image(systemName: "xmark").font(DS.Font.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }

    private var fileList: some View {
        List(viewModel.ruleFiles) { file in
            Button {
                Task { await viewModel.selectFile(file.filePath) }
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                    Text(file.fileName)
                        .font(DS.Font.body)
                    Spacer()
                    Text("v\(file.version)")
                        .font(DS.Font.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.sidebar)
    }

    private var corruptionSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Issues (\(viewModel.corruptionResults.count))")
                .font(DS.Font.sectionHeader)
                .foregroundColor(.orange)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)

            ForEach(viewModel.corruptionResults) { result in
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: severityIcon(result.severity))
                        .foregroundColor(severityColor(result.severity))
                        .font(DS.Font.caption)
                    Text(result.message)
                        .font(DS.Font.label)
                        .lineLimit(2)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        .padding(.bottom, DS.Spacing.md)
    }

    private var footer: some View {
        HStack {
            Button("Scan") {
                Task { await viewModel.runCorruptionScan() }
            }
            .disabled(viewModel.selectedFilePath == nil || viewModel.isScanning)
            .font(DS.Font.label)
            Spacer()
        }
        .padding(DS.Spacing.md)
    }

    private func severityIcon(_ severity: CorruptionSeverity) -> String {
        switch severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func severityColor(_ severity: CorruptionSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
