import AppKit

// MARK: - Dock menu

extension AppDelegate {
    /// Right-click / press-and-hold Dock icon menu. AppKit invokes this on the main
    /// thread. The items route through the same dispatcher methods as File ▸ … and the
    /// Welcome window; each of those falls back to a modal panel when there is no key
    /// window, so the menu still works when every project window is closed.
    ///
    /// Explicit `@objc`: this is an *optional* `@objc` protocol requirement implemented
    /// in an extension — Swift does not always infer `@objc` for optional-requirement
    /// witnesses outside the main class body, and without ObjC exposure AppKit would
    /// never invoke it (the Dock menu would silently never appear).
    @objc
    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(dockMenuItem(
            title: String(localized: "New Project\u{2026}"),
            action: #selector(dockNewProject)
        ))
        menu.addItem(dockMenuItem(
            title: String(localized: "New Session"),
            action: #selector(dockNewSession)
        ))
        menu.addItem(dockMenuItem(
            title: String(localized: "Open Project\u{2026}"),
            action: #selector(dockOpenProject)
        ))
        return menu
    }

    private func dockMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func dockNewProject() { createNewProject() }

    @objc private func dockNewSession() { createNewSession() }

    @objc private func dockOpenProject() { showProjectPicker() }
}
