import Foundation

// MARK: - Dialog, field, and divider size constants

extension AppConfig.UI {
    // Dialog frame sizes
    static let searchDialogWidth: Double = 500
    static let searchDialogHeight: Double = 400
    static let branchMergeSheetWidth: Double = 480
    static let codifyRuleSheetWidth: Double = 500
    static let shellOnboardingSheetWidth: Double = 480
    /// Cold-launch Welcome window dimensions. Wide enough for a 2-column
    /// "primary actions on the left, recent projects on the right" layout
    /// without forcing horizontal scrolling on the recent-project rows.
    static let welcomeWindowWidth: Double = 720
    static let welcomeWindowHeight: Double = 460
    /// Width of the right "Recents" column inside the Welcome window.
    static let welcomeRecentsColumnWidth: Double = 280
    /// Logo height inside the Welcome window's hero header.
    static let welcomeLogoHeight: Double = 48
    static let exportOptionsSheetWidth: Double = 320
    static let contextWindowAlertWidth: Double = 320
    static let interventionAlertWidth: Double = 340
    static let contextFileMinWidth: Double = 500
    static let contextFileMinHeight: Double = 300
    static let contextFileEditMinWidth: Double = 550
    static let contextFileEditMinHeight: Double = 400
    static let mainSheetMinWidth: Double = 300
    static let mainSheetIdealHeight: Double = 500
    // Field/picker widths
    static let fieldPickerWidth: Double = 200
    static let settingsFontSizeFieldWidth: Double = 50
    static let filePreviewLineNumberWidth: CGFloat = 36
    static let agentDashboardLabelWidth: Double = 80
    // Composer
    static let composerMaxWidth: Double = 700
    static let composerMinHeight: Double = 160
    static let composerMaxHeight: Double = 400
    static let composerEditorMinHeight: Double = 80
    static let composerNotesPanelWidth: Double = 340
    // Divider
    static let dividerLineWidth: Double = 1
    static let dividerHitTarget: Double = 9
    // Attachment bar
    static let attachmentBarHeight: Double = 40
    static let attachmentPillHeight: Double = 28
    static let attachmentPillCornerRadius: Double = 6
}
