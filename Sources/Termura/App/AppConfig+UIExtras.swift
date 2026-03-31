import Foundation

/// Additional UI configuration constants extracted from inline magic numbers.
extension AppConfig.UI {
    // MARK: - Window Chrome

    /// Traffic-light button horizontal offset from window edge.
    static let trafficLightX: CGFloat = 12
    /// Traffic-light button vertical offset from window top.
    static let trafficLightTopInset: CGFloat = 8
    /// Height of the traffic-light button container, measured from the live window in
    /// `adjustTrafficLights`. Written once at startup; read when the sidebar toggle renders.
    /// Default 16pt is a fallback for the brief window before measurement fires.
    @MainActor static var trafficLightContainerHeight: CGFloat = 16
    /// Derived vertical center of the traffic-light group from the top of the window.
    /// Recomputed each access so it reflects the latest measured container height.
    @MainActor static var trafficLightCenterY: CGFloat { trafficLightTopInset + trafficLightContainerHeight / 2 }
    /// Minimum leading padding to clear the traffic-light group.
    /// Based on trafficLightX(12) + 3 buttons(~52pt) + 32pt gap = 96pt.
    static let trafficLightSafeLeading: CGFloat = 96
    /// Fullscreen project-name label horizontal offset from zoom button.
    static let fullScreenLabelSpacing: CGFloat = 12
    /// Fullscreen project label font size.
    static let fullScreenLabelFontSize: CGFloat = 13
    /// Default project window width.
    static let projectWindowWidth: CGFloat = 1200
    /// Default project window height.
    static let projectWindowHeight: CGFloat = 800
    /// Minimum project window width.
    static let projectWindowMinWidth: CGFloat = 800
    /// Minimum project window height.
    static let projectWindowMinHeight: CGFloat = 500

    // MARK: - Code Editor

    /// Line number ruler width in the code editor.
    static let lineNumberRulerWidth: CGFloat = 60
    /// Line spacing (leading) added above each code editor line.
    static let codeEditorLineSpacing: CGFloat = 6
    /// Text inset (padding) inside the code editor text view.
    static let codeEditorTextInset: CGFloat = 8
    /// Indent width in characters for the saveable text view.
    static let editorIndentWidth = 4
    /// Line number font size reduction relative to editor size.
    static let lineNumberFontSizeReduction: CGFloat = 3

    // MARK: - Editor Background

    /// Dark editor background white channel value.
    static let editorBackgroundDark: CGFloat = 0.13
    /// Light editor background white channel value.
    static let editorBackgroundLight: CGFloat = 0.97

    // MARK: - File Preview

    /// File preview zoom step.
    static let previewZoomStep: Double = 0.25
    /// File preview minimum zoom.
    static let previewZoomMin: Double = 0.25
    /// File preview maximum zoom.
    static let previewZoomMax: Double = 4.0

    // MARK: - Window Tags

    /// NSView tag for the fullscreen project-name label (find/remove).
    static let fullScreenLabelTag = 9901

    // MARK: - Animations

    /// Composer toggle spring response.
    static let composerSpringResponse: Double = 0.35
    /// Composer toggle spring damping fraction.
    static let composerSpringDamping: Double = 0.85
    /// Composer dismiss animation duration.
    static let composerDismissDuration: Double = 0.2

    // MARK: - Miscellaneous

    /// Small progress indicator scale.
    static let progressIndicatorScale: CGFloat = 0.7
    /// Theme grid column count in the theme picker.
    static let themeGridColumns = 4
}
