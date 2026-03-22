import SwiftUI

// MARK: - Panel Header Style

/// Consistent uppercase panel header used in sidebar, timeline, metadata, etc.
struct PanelHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.Font.panelHeader)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}

extension View {
    func panelHeaderStyle() -> some View {
        modifier(PanelHeaderModifier())
    }
}

// MARK: - Section Label Style

/// Uppercase label for metadata item titles and form section headers.
struct SectionLabelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.Font.sectionHeader)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}

extension View {
    func sectionLabelStyle() -> some View {
        modifier(SectionLabelModifier())
    }
}

// MARK: - Hover Row Background

/// Interactive list row with hover highlight and rounded corners.
struct HoverRowModifier: ViewModifier {
    let isHovered: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                isHovered
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(DS.Opacity.selected)
                    : Color.clear
            )
            .cornerRadius(cornerRadius)
    }
}

extension View {
    func hoverRow(isHovered: Bool, cornerRadius: CGFloat = DS.Radius.sm) -> some View {
        modifier(HoverRowModifier(isHovered: isHovered, cornerRadius: cornerRadius))
    }
}
