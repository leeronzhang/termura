import Foundation

/// Groups per-session view objects whose lifetimes are tied to a single terminal session.
/// Owned by `ProjectContext.sessionViewStates` — views receive these via `@ObservedObject`.
///
/// This avoids the fragile `@StateObject(wrappedValue:)` in `init` pattern where shared
/// references (OutputStore → TerminalViewModel) can desynchronise if SwiftUI re-invokes
/// the view's initialiser without discarding the old `@StateObject` instance.
@MainActor
final class SessionViewState: ObservableObject {
    let outputStore: OutputStore
    var viewModel: TerminalViewModel
    var editorViewModel: EditorViewModel
    let modeController: InputModeController
    let timeline: SessionTimeline
    let editorHandle = EditorViewHandle()

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
