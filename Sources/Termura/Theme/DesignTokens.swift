import SwiftUI

/// Centralized design tokens for consistent spacing, typography, radii, and opacity.
/// All magic numbers in views must reference `DS` instead of inline literals.
enum DS {

    // MARK: - Spacing Scale

    enum Spacing {
        /// 2pt — hairline gaps, inline icon-to-text
        static let xs: CGFloat = 2
        /// 4pt — tight vertical stacks, badge padding
        static let sm: CGFloat = 4
        /// 8pt — standard inner padding, HStack spacing
        static let md: CGFloat = 8
        /// 12pt — panel padding, section gaps
        static let lg: CGFloat = 12
        /// 16pt — major section separation
        static let xl: CGFloat = 16
        /// 20pt — sheet padding
        static let xxl: CGFloat = 20
        /// 24pt — hero/alert padding
        static let xxxl: CGFloat = 24
    }

    // MARK: - Corner Radius

    enum Radius {
        /// 2pt — color swatches, tiny elements
        static let xs: CGFloat = 2
        /// 4pt — badges, inline tags, timeline rows
        static let sm: CGFloat = 4
        /// 6pt — list rows, session cards
        static let md: CGFloat = 6
        /// 8pt — panels, sheets, cards
        static let lg: CGFloat = 8
    }

    // MARK: - Typography

    enum Font {
        /// 10pt — meta labels, timestamps, uppercase headers
        static let caption = SwiftUI.Font.system(size: 10)
        /// 10pt monospaced — token counts, small data
        static let captionMono = SwiftUI.Font.system(size: 10, design: .monospaced)
        /// 10pt semibold — section headers (UPPERCASE)
        static let sectionHeader = SwiftUI.Font.system(size: 10, weight: .semibold)
        /// 11pt — secondary labels, sidebar subtitle, timeline text
        static let label = SwiftUI.Font.system(size: 11)
        /// 11pt semibold — panel headers
        static let panelHeader = SwiftUI.Font.system(size: 11, weight: .semibold)
        /// 11pt monospaced — code snippets, directory paths
        static let labelMono = SwiftUI.Font.system(size: 11, design: .monospaced)
        /// 11pt medium — toolbar labels, agent names
        static let labelMedium = SwiftUI.Font.system(size: 11, weight: .medium)
        /// 12pt — list items, form fields
        static let body = SwiftUI.Font.system(size: 12)
        /// 12pt medium — emphasized body text
        static let bodyMedium = SwiftUI.Font.system(size: 12, weight: .medium)
        /// 12pt monospaced — code editors, diffs
        static let bodyMono = SwiftUI.Font.system(size: 12, design: .monospaced)
        /// 13pt — primary text, session titles
        static let title3 = SwiftUI.Font.system(size: 13)
        /// 13pt medium — metadata values, command counts
        static let title3Medium = SwiftUI.Font.system(size: 13, weight: .medium)
        /// 14pt medium — toolbar buttons, footer icons
        static let title2 = SwiftUI.Font.system(size: 14, weight: .medium)
        /// 15pt — search field input
        static let searchField = SwiftUI.Font.system(size: 15)
        /// 16pt semibold — view titles, empty state headings
        static let title1 = SwiftUI.Font.system(size: 16, weight: .semibold)
    }

    // MARK: - Opacity

    enum Opacity {
        /// 0.08 — subtle tinted backgrounds (feature cards)
        static let tint: Double = 0.08
        /// 0.1 — attention/highlight backgrounds
        static let highlight: Double = 0.1
        /// 0.15 — selected state backgrounds, hover
        static let selected: Double = 0.15
        /// 0.3 — active session highlight, muted overlays
        static let muted: Double = 0.3
        /// 0.35 — border strokes
        static let border: Double = 0.35
        /// 0.5 — dimmed text, disabled states
        static let dimmed: Double = 0.5
        /// 0.6 — secondary content, muted text
        static let secondary: Double = 0.6
        /// 0.7 — strong secondary
        static let strong: Double = 0.7
    }

    // MARK: - Sizes

    enum Size {
        /// 6pt — small indicator dots (exit code, timeline)
        static let dotSmall: CGFloat = 6
        /// 8pt — standard indicator dots (status, color label)
        static let dotMedium: CGFloat = 8
        /// 16pt — icon frame width (search results)
        static let iconFrame: CGFloat = 16
        /// Divider height inside toolbars
        static let toolbarDivider: CGFloat = 16
    }

    // MARK: - Animation

    enum Animation {
        /// Standard fade out duration
        static let fadeOut: Double = 0.3
    }
}
