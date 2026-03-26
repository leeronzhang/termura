import Foundation

/// Additional UI configuration constants extracted from inline magic numbers.
extension AppConfig.UI {
    // MARK: - Window Chrome

    /// Traffic-light button horizontal offset from window edge.
    static let trafficLightX: CGFloat = 12
    /// Traffic-light button vertical offset from window top.
    static let trafficLightTopInset: CGFloat = 8
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
    /// Dark editor background white channel value.
    static let editorBackgroundDark: CGFloat = 0.13
    /// Light editor background white channel value.
    static let editorBackgroundLight: CGFloat = 0.97

    // MARK: - Composer Overlay

    /// Composer card corner radius.
    static let composerCornerRadius: CGFloat = 12
    /// Composer shadow card opacity.
    static let composerShadowOpacity: Double = 0.4
    /// Composer shadow radius.
    static let composerShadowRadius: CGFloat = 24
    /// Composer shadow Y offset.
    static let composerShadowY: CGFloat = 8
    /// Close-button font size for composer overlay.
    static let composerCloseIconSize: CGFloat = 16
    /// Snippet row corner radius.
    static let snippetRowCornerRadius: CGFloat = 6
    /// Save-confirmation badge display duration (nanoseconds).
    static let saveConfirmDurationNanoseconds: UInt64 = 1_500_000_000

    // MARK: - File Preview

    /// File preview zoom step.
    static let previewZoomStep: Double = 0.25
    /// File preview minimum zoom.
    static let previewZoomMin: Double = 0.25
    /// File preview maximum zoom.
    static let previewZoomMax: Double = 4.0

    // MARK: - Miscellaneous

    /// Small progress indicator scale.
    static let progressIndicatorScale: CGFloat = 0.7
    /// Theme grid column count in the theme picker.
    static let themeGridColumns = 4
}
