import AppKit
import SwiftUI

extension TerminalAreaView {
    // MARK: - Terminal / output stack

    @ViewBuilder
    var terminalAndOutputArea: some View {
        VStack(spacing: 0) {
            if !isCompact {
                projectPathBar
            }
            ZStack(alignment: .bottom) {
                TerminalContainerView(
                    viewModel: viewModel,
                    engine: engine,
                    theme: themeManager.current,
                    fontFamily: fontSettings.terminalFontFamily,
                    fontSize: fontSettings.terminalFontSize,
                    isComposerActive: commandRouter.showComposer && isFocusedPane
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppUI.Spacing.xxl)
                .background(themeManager.current.background)

                if commandRouter.showComposer && isFocusedPane {
                    composerOverlayContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.current.background)
    }

    /// VStack-based bottom sheet: backdrop fills the space above the composer, composer sits
    /// at the fixed bottom. Avoids GeometryReader (known async sizing issue inside
    /// ZStack+NSViewRepresentable hierarchies on first layout pass).
    @ViewBuilder
    private var composerOverlayContent: some View {
        VStack(spacing: 0) {
            // Backdrop — covers the terminal above the composer.
            // Uses AppKitClickableOverlay (not .onTapGesture) because SwiftTerm's
            // TerminalDragContainerView and EditorTextView are real AppKit NSViews
            // that AppKit hitTest routes events before SwiftUI gestures can fire.
            // Backdrop and composer transitions must NOT carry their own .animation()
            // modifiers — they conflict with the parent withAnimation in toggleComposer /
            // toggleComposerWithNotes / dismissComposer, and on the first-ever insertion
            // the conflicting pipelines can leave ComposerOverlayView stuck at its
            // .move(edge: .bottom) offscreen position (visible as "no composer").
            // Letting the parent withAnimation drive all transitions fixes this.
            themeManager.current.background
                .opacity(AppUI.Opacity.strong)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(AppKitClickableOverlay(action: { commandRouter.dismissComposer() }))
                .transition(.opacity)

            ComposerOverlayView(
                editorViewModel: editorViewModel,
                editorHandle: editorHandle,
                isNotesActive: commandRouter.isComposerNotesActive,
                onToggleNotes: { commandRouter.toggleComposerNotes() },
                onDismiss: { commandRouter.dismissComposer() }
            )
            .onAppear {
                let vm = editorViewModel
                let handle = editorHandle
                commandRouter.composerInsertHandler = { text in
                    if let textView = handle.textView {
                        textView.appendTextAtEnd("\n" + text)
                        textView.window?.makeFirstResponder(textView)
                    } else {
                        vm.appendText("\n" + text)
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .bottom),
                removal: .opacity
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension String {
    /// Wraps the string in single quotes with proper escaping for shell use.
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
