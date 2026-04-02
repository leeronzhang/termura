import AppKit
import GhosttyKit

// MARK: - Right-click context menu

extension GhosttyTerminalView {
    // MARK: - Selection reading

    /// Reads the currently selected text from the ghostty surface.
    /// Returns nil if no text is selected or the surface is unavailable.
    func readSelectedText() -> String? {
        guard let surface else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        let result = String(cString: text.text)
        guard !result.isEmpty else { return nil }
        return result
    }

    // MARK: - Menu construction

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let selection = readSelectedText()
        let hasSelection = selection != nil

        // Copy
        let copyItem = NSMenuItem(title: String(localized: "Copy"), action: #selector(copy(_:)), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = .command
        copyItem.isEnabled = hasSelection
        menu.addItem(copyItem)

        // Paste
        let pasteItem = NSMenuItem(title: String(localized: "Paste"), action: #selector(paste(_:)), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = .command
        menu.addItem(pasteItem)

        // Select All
        let selectAllItem = NSMenuItem(title: String(localized: "Select All"), action: #selector(selectAll(_:)), keyEquivalent: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        menu.addItem(selectAllItem)

        menu.addItem(.separator())

        // Quote in Composer
        let quoteItem = NSMenuItem(title: String(localized: "Quote in Composer"), action: #selector(performQuote(_:)), keyEquivalent: "")
        quoteItem.isEnabled = hasSelection && contextMenuActions.onQuoteInComposer != nil
        menu.addItem(quoteItem)

        // Ask About This
        let askItem = NSMenuItem(title: String(localized: "Ask About This"), action: #selector(performAsk(_:)), keyEquivalent: "")
        askItem.isEnabled = hasSelection && contextMenuActions.onAskAboutThis != nil
        menu.addItem(askItem)

        // Send to Notes
        let notesItem = NSMenuItem(title: String(localized: "Send to Notes"), action: #selector(performSendToNotes(_:)), keyEquivalent: "")
        notesItem.isEnabled = hasSelection && contextMenuActions.onSendToNotes != nil
        menu.addItem(notesItem)

        menu.addItem(.separator())

        // Clear Terminal
        let clearItem = NSMenuItem(title: String(localized: "Clear"), action: #selector(performClearScreen(_:)), keyEquivalent: "")
        clearItem.isEnabled = contextMenuActions.onClearTerminal != nil
        menu.addItem(clearItem)

        // Cache selection at menu-build time for async action dispatch.
        menuCachedSelection = selection
        return menu
    }

    // MARK: - Standard actions

    @IBAction func copy(_ sender: Any?) {
        guard let surface else { return }
        let action = "copy_to_clipboard"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    @objc override func selectAll(_ sender: Any?) {
        guard let surface else { return }
        let action = "select_all"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    // MARK: - Custom actions

    @objc private func performQuote(_ sender: Any?) {
        guard let text = menuCachedSelection else { return }
        let quoted = formatAsQuote(text)
        contextMenuActions.onQuoteInComposer?(quoted)
    }

    @objc private func performAsk(_ sender: Any?) {
        guard let text = menuCachedSelection else { return }
        let quoted = formatAsQuote(text)
        let prompt = "Question: \n\n\(quoted)"
        contextMenuActions.onAskAboutThis?(prompt)
    }

    @objc private func performSendToNotes(_ sender: Any?) {
        guard let text = menuCachedSelection else { return }
        contextMenuActions.onSendToNotes?(text)
    }

    @objc private func performClearScreen(_ sender: Any?) {
        contextMenuActions.onClearTerminal?()
    }

    // MARK: - Helpers

    private func formatAsQuote(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
    }
}
