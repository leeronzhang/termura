import SwiftUI

extension CommandRouter {
    func toggleSidebar() {
        // User-initiated toggle overrides any pending auto-restore.
        sidebarWasHiddenForNotes = false
        showSidebar.toggle()
    }

    func toggleComposer() {
        if showComposer {
            // Route through dismissComposer() so tabBeforeComposer is restored
            // and isComposerNotesActive is cleared. A bare showComposer.toggle()
            // would leave the sidebar on .notes and orphan tabBeforeComposer.
            dismissComposer()
        } else {
            withAnimation(.spring(
                response: AppConfig.UI.composerSpringResponse,
                dampingFraction: AppConfig.UI.composerSpringDamping
            )) {
                showComposer = true
            }
        }
    }

    func dismissComposer() {
        composerInsertHandler = nil
        if let previous = tabBeforeComposer {
            selectedSidebarTab = previous
            tabBeforeComposer = nil
        }
        isComposerNotesActive = false
        // Restore sidebar visibility if it was auto-revealed for notes mode.
        let shouldHideSidebar = sidebarWasHiddenForNotes
        sidebarWasHiddenForNotes = false
        withAnimation(.easeOut(duration: AppConfig.UI.composerDismissDuration)) {
            showComposer = false
            if shouldHideSidebar { showSidebar = false }
        }
    }

    /// Toggles the sidebar Notes tab from the Composer notes button.
    /// Both isComposerNotesActive and selectedSidebarTab change in the same call so
    /// SwiftUI batches them into one render pass — no intermediate notesEmptyState flash.
    func toggleComposerNotes() {
        if !isComposerNotesActive {
            tabBeforeComposer = selectedSidebarTab
            // Auto-reveal sidebar if hidden, mirroring toggleComposerWithNotes() behaviour.
            let needsReveal = !showSidebar
            if needsReveal { sidebarWasHiddenForNotes = true }
            // isComposerNotesActive and selectedSidebarTab must change in the same
            // withAnimation transaction so restoreContentTabOnSidebarSwitch sees the
            // flag as true when the onChange fires — prevents a stale tab restore.
            withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
                isComposerNotesActive = true
                selectedSidebarTab = .notes
                if needsReveal { showSidebar = true }
            }
        } else if let previous = tabBeforeComposer {
            // Close: both state changes inside one animation block so SwiftUI
            // produces a single render pass — prevents notesEmptyState flashing
            // when selectedSidebarTab is still .notes but isComposerNotesActive
            // has already flipped to false.
            tabBeforeComposer = nil
            let shouldHideSidebar = sidebarWasHiddenForNotes
            sidebarWasHiddenForNotes = false
            withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
                isComposerNotesActive = false
                selectedSidebarTab = previous
                if shouldHideSidebar { showSidebar = false }
            }
        }
    }

    /// Opens the Composer and activates the Notes sidebar simultaneously (Shift+Cmd+K).
    /// If the Composer is already open with notes active, dismisses it.
    /// If the Composer is open without notes, activates notes mode without closing.
    /// If the sidebar is hidden, auto-reveals it and restores the hidden state on dismiss.
    func toggleComposerWithNotes() {
        if showComposer, isComposerNotesActive {
            dismissComposer()
            return
        }
        // Activate notes mode — capture tab before composer opens if needed.
        if !isComposerNotesActive {
            tabBeforeComposer = selectedSidebarTab
        }
        // Auto-reveal sidebar if hidden so the notes list is immediately visible.
        let needsReveal = !showSidebar
        if needsReveal { sidebarWasHiddenForNotes = true }
        // All state changes must happen inside the same withAnimation transaction so
        // restoreContentTabOnSidebarSwitch sees isComposerNotesActive == true when the
        // .onChange(of: selectedSidebarTab) fires — otherwise the sidebar switch is
        // treated as permanent and the content tab is restored from history.
        withAnimation(.spring(
            response: AppConfig.UI.composerSpringResponse,
            dampingFraction: AppConfig.UI.composerSpringDamping
        )) {
            isComposerNotesActive = true
            showComposer = true
            selectedSidebarTab = .notes
            if needsReveal { showSidebar = true }
        }
    }
}
