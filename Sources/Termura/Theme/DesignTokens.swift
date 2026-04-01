import SwiftUI

/// Centralized design tokens for consistent spacing, typography, radii, and opacity.
/// All magic numbers in views must reference `DS` instead of inline literals.
enum AppUI {
    // MARK: - Spacing Scale

    enum Spacing {
        /// 1pt — hairline, single-pixel gaps
        static let xxs: CGFloat = 1
        /// 2pt — inline icon-to-text, tight stacks
        static let xs: CGFloat = 2
        /// 4pt — badge padding, compact gaps
        static let sm: CGFloat = 4
        /// 6pt — row vertical padding (half-grid)
        static let smMd: CGFloat = 6
        /// 8pt — standard inner padding, HStack spacing
        static let md: CGFloat = 8
        /// 10pt — content padding within rows
        static let mdLg: CGFloat = 10
        /// 12pt — panel padding, section gaps
        static let lg: CGFloat = 12
        /// 14pt — panel header vertical breathing room
        static let lgXl: CGFloat = 14
        /// 16pt — major section separation
        static let xl: CGFloat = 16
        /// 20pt — sheet padding
        static let xxl: CGFloat = 20
        /// 24pt — hero/alert padding
        static let xxxl: CGFloat = 24
        /// 32pt — large empty state top padding
        static let xxxxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum Radius {
        /// 0pt — sharp corners for all internal UI elements
        static let xs: CGFloat = 0
        /// 0pt — sharp corners for all internal UI elements
        static let sm: CGFloat = 0
        /// 0pt — sharp corners for all internal UI elements
        static let md: CGFloat = 0
        /// 0pt — sharp corners for all internal UI elements
        static let lg: CGFloat = 0
        /// 0pt — sharp corners for all internal UI elements
        static let xl: CGFloat = 0
    }

    // MARK: - Typography

    enum Font {
        /// 9pt — tiny icons (close buttons)
        static let micro = SwiftUI.Font.system(size: 9)
        /// 10pt — meta labels, timestamps, uppercase headers
        static let caption = SwiftUI.Font.system(size: 10)
        /// 10pt monospaced — token counts, small data
        static let captionMono = SwiftUI.Font.custom(AppConfig.Fonts.terminalFamily, size: 10)
        /// 10pt medium — section headers (UPPERCASE)
        static let sectionHeader = SwiftUI.Font.system(size: 10, weight: .medium)
        /// 11pt — secondary labels, sidebar subtitle, timeline text
        static let label = SwiftUI.Font.system(size: 11)
        /// 11pt semibold — panel headers
        static let panelHeader = SwiftUI.Font.system(size: 11, weight: .semibold)
        /// 11pt monospaced — code snippets, directory paths
        static let labelMono = SwiftUI.Font.custom(AppConfig.Fonts.terminalFamily, size: 11)
        /// 11pt medium — toolbar labels, agent names
        static let labelMedium = SwiftUI.Font.system(size: 11, weight: .medium)
        /// 12pt — list items, form fields
        static let body = SwiftUI.Font.system(size: 12)
        /// 12pt medium — emphasized body text
        static let bodyMedium = SwiftUI.Font.system(size: 12, weight: .medium)
        /// 12pt monospaced — code editors, diffs
        static let bodyMono = SwiftUI.Font.custom(AppConfig.Fonts.terminalFamily, size: 12)
        /// 13pt — primary text, session titles
        static let title3 = SwiftUI.Font.system(size: 13)
        /// 13pt medium — metadata values, command counts
        static let title3Medium = SwiftUI.Font.system(size: 13, weight: .medium)
        /// 14pt medium — toolbar buttons, footer icons
        static let title2 = SwiftUI.Font.system(size: 14, weight: .medium)
        /// 15pt — search field input
        static let searchField = SwiftUI.Font.system(size: 15)
        /// 16pt medium — view titles, empty state headings
        static let title1 = SwiftUI.Font.system(size: 16, weight: .medium)
        /// 16pt semibold — editable titles (note title field)
        static let title1Semibold = SwiftUI.Font.system(size: 16, weight: .semibold)
        /// 24pt — empty state hero icons
        static let hero = SwiftUI.Font.system(size: 24, weight: .light)
        /// 36pt — alert / warning dialog icons
        static let alertIcon = SwiftUI.Font.system(size: 36)
        /// 13pt — toolbar toggle icons (timeline, metadata panel)
        static let toolbarIcon = SwiftUI.Font.system(size: 13)
        /// 13pt monospaced — project path, working directory display
        static let pathMono = SwiftUI.Font.custom(AppConfig.Fonts.terminalFamily, size: 13)
        /// 9pt semibold — folder / tree chevrons
        static let chevron = SwiftUI.Font.system(size: 9, weight: .semibold)
        /// 9pt medium — attachment size labels, compact metadata chips
        static let microMedium = SwiftUI.Font.system(size: 9, weight: .medium)
        /// 10pt bold monospaced — git status badges (M, A, D, U, R)
        static let gitBadge = SwiftUI.Font.custom(AppConfig.Fonts.terminalFamily, size: 10).bold()
        /// 14pt — sidebar section labels, overlay titles (regular weight)
        static let title2Regular = SwiftUI.Font.system(size: 14)
        /// 15pt — sidebar tab bar icons
        static let tabBarIcon = SwiftUI.Font.system(size: 15)
        /// 40pt light — onboarding / sheet hero icons
        static let sheetIcon = SwiftUI.Font.system(size: 40, weight: .light)
    }

    // MARK: - Opacity

    enum Opacity {
        /// 0.06 — barely visible tints (hover backgrounds on dark)
        static let whisper: Double = 0.06
        /// 0.08 — subtle tinted backgrounds (feature cards)
        static let tint: Double = 0.08
        /// 0.1 — attention/highlight backgrounds
        static let highlight: Double = 0.1
        /// 0.15 — selected state backgrounds, hover
        static let selected: Double = 0.15
        /// 0.25 — soft borders, faint strokes
        static let softBorder: Double = 0.25
        /// 0.3 — active session highlight, muted overlays
        static let muted: Double = 0.3
        /// 0.35 — border strokes
        static let border: Double = 0.35
        /// 0.4 — tertiary text
        static let tertiary: Double = 0.4
        /// 0.5 — dimmed text, disabled states
        static let dimmed: Double = 0.5
        /// 0.6 — secondary content, muted text
        static let secondary: Double = 0.6
        /// 0.7 — strong secondary
        static let strong: Double = 0.7
        /// 0.25 — tab bar background overlay
        static let tabBar: Double = 0.25
        /// 0.1 — diff addition line highlight
        static let diffAddition: Double = 0.1
        /// 0.1 — diff removal line highlight
        static let diffRemoval: Double = 0.1
        /// 0.5 — modal backdrop overlay
        static let backdrop: Double = 0.5
    }

    // MARK: - Sizes

    enum Size {
        /// 6pt — small indicator dots (exit code, timeline)
        static let dotSmall: CGFloat = 6
        /// 7pt — medium-small dots (timeline exit codes)
        static let dotMediumSmall: CGFloat = 7
        /// 8pt — standard indicator dots (status, color label)
        static let dotMedium: CGFloat = 8
        /// 16pt — icon frame width (search results)
        static let iconFrame: CGFloat = 16
        /// 18pt — icon frame width (feature rows)
        static let iconFrameLarge: CGFloat = 18
        /// Divider height inside toolbars
        static let toolbarDivider: CGFloat = 16
        /// 13pt — file type icon in sidebar rows
        static let fileTypeIcon: CGFloat = 13
        /// 14pt — theme checkbox indicator
        static let themeCheckbox: CGFloat = 14
        /// 7pt — directory expansion chevron
        static let directoryChevron: CGFloat = 7
        /// 1pt — branch indicator line width
        static let branchIndicatorLine: CGFloat = 1
    }

    // MARK: - Animation

    enum Animation {
        /// Standard fade out duration
        static let fadeOut: Double = 0.3
        /// Quick micro-interaction
        static let quick: Double = 0.15
        /// Panel show/hide
        static let panel: Double = 0.2
        /// Sidebar tab switch
        static let tabSwitch: Double = 0.25
        /// Status badge pulse cycle
        static let pulse: Double = 1.0
    }

    // MARK: - Scale Factors

    enum Scale {
        /// Agent status badge pulse max
        static let pulseMax: Double = 1.2
        /// Agent status badge pulse min
        static let pulseMin: Double = 0.8
    }
}
