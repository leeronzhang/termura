import SwiftUI

/// Collapsible footer panel listing notes that link to the current note via
/// `[[wiki-link]]` syntax. Default state is collapsed; expanding reveals a
/// scrollable list with click-to-navigate. Hidden entirely when there are no
/// inbound links so the note body claims all the space.
///
/// Sits below the rendered note in `NoteTabContentView`'s reading mode.
struct BacklinksPanel: View {
    let backlinks: [(id: NoteID, title: String)]
    let onOpenBacklink: (String) -> Void

    @State private var isExpanded = false

    var body: some View {
        if backlinks.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                header
                if isExpanded {
                    list
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(AppUI.Opacity.tint))
            .accessibilityElement(children: .contain)
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: AppUI.Animation.tabSwitch)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: AppUI.Spacing.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(AppUI.Font.micro)
                    .foregroundColor(.secondary)
                    .frame(width: AppUI.Size.chevronFrame)
                Text("Backlinks")
                    .font(AppUI.Font.panelHeader)
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
                Text("\(backlinks.count)")
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
                Spacer()
            }
            .padding(.horizontal, AppUI.Spacing.xxxl)
            .padding(.vertical, AppUI.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Backlinks (\(backlinks.count))")
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
                ForEach(backlinks, id: \.id) { entry in
                    backlinkRow(title: entry.title)
                }
            }
            .padding(.horizontal, AppUI.Spacing.xxxl)
            .padding(.bottom, AppUI.Spacing.md)
        }
        .frame(maxHeight: 160)
    }

    private func backlinkRow(title: String) -> some View {
        Button {
            onOpenBacklink(title)
        } label: {
            HStack(spacing: AppUI.Spacing.sm) {
                Image(systemName: "arrow.uturn.backward")
                    .font(AppUI.Font.micro)
                    .foregroundColor(.brandGreen.opacity(AppUI.Opacity.dimmed))
                Text("[[\(title)]]")
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, AppUI.Spacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(title)")
        .accessibilityLabel("Open backlinking note \(title)")
    }
}
