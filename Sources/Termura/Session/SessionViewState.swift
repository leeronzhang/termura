import Foundation

/// Groups per-session view objects whose lifetimes are tied to a single terminal session.
/// Owned by `SessionViewStateManager` — views receive these via `@Bindable` for binding
/// support while `@Observable` drives automatic SwiftUI re-renders.
@Observable
@MainActor
final class SessionViewState {
    let outputStore: OutputStore
    var viewModel: TerminalViewModel
    var editorViewModel: EditorViewModel
    let modeController: InputModeController
    let timeline: SessionTimeline
    let editorHandle = EditorViewHandle()
    /// Whether the session-info metadata panel is visible in single-pane mode.
    /// In dual-pane mode, CommandRouter.showDualPaneMetadata takes precedence.
    var showMetadata: Bool = true

    init(
        outputStore: OutputStore,
        viewModel: TerminalViewModel,
        editorViewModel: EditorViewModel,
        modeController: InputModeController,
        timeline: SessionTimeline
    ) {
        self.outputStore = outputStore
        self.viewModel = viewModel
        self.editorViewModel = editorViewModel
        self.modeController = modeController
        self.timeline = timeline
    }
}
