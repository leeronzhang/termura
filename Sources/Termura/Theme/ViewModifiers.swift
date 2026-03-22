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
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        isHovered
                            ? Color(nsColor: .selectedContentBackgroundColor).opacity(DS.Opacity.highlight)
                            : Color.clear
                    )
            )
    }
}

extension View {
    func hoverRow(isHovered: Bool, cornerRadius: CGFloat = DS.Radius.sm) -> some View {
        modifier(HoverRowModifier(isHovered: isHovered, cornerRadius: cornerRadius))
    }
}

// MARK: - Floating Card Shadow

/// Subtle shadow for floating overlays (editor card, intervention toolbar).
struct FloatingCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(
                color: .black.opacity(DS.Shadow.cardOpacity),
                radius: DS.Shadow.cardRadius,
                y: DS.Shadow.cardY
            )
    }
}

extension View {
    func floatingCard() -> some View {
        modifier(FloatingCardModifier())
    }
}

// MARK: - Conditional Modifier

extension View {
    /// Applies a modifier only when the condition is true.
    @ViewBuilder
    func `if`<Transform: View>(
        _ condition: Bool,
        transform: (Self) -> Transform
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Smooth Panel Transition

extension AnyTransition {
    static var panelSlide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    static var panelSlideTrailing: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
}
