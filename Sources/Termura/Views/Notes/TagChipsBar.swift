import SwiftUI

/// Horizontal scrolling bar of tag chips for filtering notes in the sidebar.
struct TagChipsBar: View {
    let tags: [(tag: String, count: Int)]
    let selectedTag: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppUI.Spacing.sm) {
                ForEach(tags, id: \.tag) { item in
                    TagChip(
                        tag: item.tag,
                        count: item.count,
                        isSelected: selectedTag == item.tag,
                        onTap: {
                            onSelect(selectedTag == item.tag ? nil : item.tag)
                        }
                    )
                }
            }
            .padding(.horizontal, AppUI.Spacing.xxxl)
        }
        .padding(.vertical, AppUI.Spacing.sm)
    }
}

/// Single tag chip button with label, count, and selected state.
private struct TagChip: View {
    let tag: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppUI.Spacing.xxs) {
                Text(tag)
                Text("\(count)")
                    .opacity(0.6)
            }
            .font(AppUI.Font.micro)
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, AppUI.Spacing.md)
            .padding(.vertical, AppUI.Spacing.xxs)
            .background(
                Capsule().fill(isSelected ? Color.brandGreen : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by tag: \(tag)")
        .accessibilityValue(isSelected ? "Active" : "")
    }
}
