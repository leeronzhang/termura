import AppKit

extension AppDelegate {
    // MARK: - Titlebar helpers

    func disableTitlebarEffect(in window: NSWindow) {
        guard let themebarParent = window.contentView?.superview else { return }
        for container in themebarParent.subviews {
            let name = String(describing: type(of: container))
            guard name.contains("NSTitlebarContainerView") else { continue }
            deactivateEffectViews(in: container)
        }
    }

    func deactivateEffectViews(in view: NSView) {
        if let effectView = view as? NSVisualEffectView,
           effectView.state != .inactive || !effectView.isHidden {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            effectView.state = .inactive
            effectView.isHidden = true
            CATransaction.commit()
        }
        for child in view.subviews {
            deactivateEffectViews(in: child)
        }
    }

    func trafficLightContainer(in window: NSWindow) -> NSView? {
        window.standardWindowButton(.closeButton)?.superview
    }

    /// Electron approach (VS Code/Discord/Notion): expand NSTitlebarContainerView
    /// height and position each button individually via setFrameOrigin.
    /// Called on every resize to keep buttons pinned.
    func adjustTrafficLights(in window: NSWindow) {
        guard let closeBtn = window.standardWindowButton(.closeButton),
              let miniBtn = window.standardWindowButton(.miniaturizeButton),
              let zoomBtn = window.standardWindowButton(.zoomButton),
              let titlebarContainer = closeBtn.superview?.superview else { return }

        let buttonHeight = closeBtn.frame.height
        let buttonWidth = closeBtn.frame.width
        let buttonSpacing = miniBtn.frame.minX - closeBtn.frame.maxX
        let topInset = AppConfig.UI.trafficLightTopInset
        let leftMargin = AppConfig.UI.trafficLightX

        // Expand NSTitlebarContainerView height to accommodate the custom inset.
        let containerHeight = topInset + buttonHeight + 4
        var containerFrame = titlebarContainer.frame
        let topEdge = containerFrame.origin.y + containerFrame.size.height
        containerFrame.size.height = containerHeight
        containerFrame.origin.y = topEdge - containerHeight
        titlebarContainer.frame = containerFrame

        // Button y within container (y=0 is bottom in AppKit coordinates).
        let buttonY = containerHeight - topInset - buttonHeight

        closeBtn.setFrameOrigin(NSPoint(x: leftMargin, y: buttonY))
        miniBtn.setFrameOrigin(NSPoint(
            x: leftMargin + buttonWidth + buttonSpacing, y: buttonY
        ))
        zoomBtn.setFrameOrigin(NSPoint(
            x: leftMargin + 2 * (buttonWidth + buttonSpacing), y: buttonY
        ))

        AppConfig.UI.trafficLightContainerHeight = containerHeight
    }

    /// Re-apply all titlebar transparency properties and suppress effect views.
    /// AppKit resets these during window activation — force them all back in one pass.
    /// Caller wraps in `CATransaction.setDisableActions(true)`.
    func suppressTitlebarChrome(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        disableTitlebarEffect(in: window)
    }

    // MARK: - KVO guards

    /// KVO guard for `titlebarAppearsTransparent`: if AppKit resets it
    /// during a SwiftUI layout pass or window activation, revert in the same
    /// run-loop tick so the titlebar never visibly rebuilds.
    func installTitlebarPropertyKVOGuard(for window: NSWindow) {
        titlebarPropertyKVO = window.observe(
            \.titlebarAppearsTransparent, options: [.new]
        ) { window, change in
            MainActor.assumeIsolated {
                guard let newValue = change.newValue, !newValue else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.titlebarSeparatorStyle = .none
                CATransaction.commit()
            }
        }
    }

    /// Install KVO observers on all titlebar NSVisualEffectViews so that any
    /// state reset by AppKit is immediately reverted to `.inactive` + hidden.
    ///
    /// - Parameter force: When `true`, tears down existing observers and reinstalls
    ///   unconditionally. When `false`, skips if the view set hasn't changed.
    func installTitlebarEffectKVOGuard(for window: NSWindow, force: Bool) {
        let currentViews = titlebarEffectViews(in: window)
        let currentIDs = Set(currentViews.map { ObjectIdentifier($0) })

        if !force, currentIDs == titlebarEffectObservedViews,
           !titlebarEffectKVOObservers.isEmpty {
            return
        }

        titlebarEffectKVOObservers.removeAll()
        titlebarEffectObservedViews.removeAll()

        guard let themeFrame = window.contentView?.superview else { return }
        for sub in themeFrame.subviews {
            let name = String(describing: type(of: sub))
            guard name.contains("NSTitlebarContainerView") else { continue }
            collectEffectViewKVO(in: sub)
        }

        titlebarEffectObservedViews = currentIDs
    }

    /// Tear down all titlebar KVO guards (used when entering fullscreen).
    func tearDownTitlebarKVOGuards() {
        titlebarPropertyKVO = nil
        titlebarEffectKVOObservers.removeAll()
        titlebarEffectObservedViews.removeAll()
    }

    // MARK: - Private KVO helpers

    private func titlebarEffectViews(in window: NSWindow) -> [NSVisualEffectView] {
        guard let themeFrame = window.contentView?.superview else { return [] }
        var result: [NSVisualEffectView] = []
        for sub in themeFrame.subviews {
            let name = String(describing: type(of: sub))
            guard name.contains("NSTitlebarContainerView") else { continue }
            collectEffectViews(in: sub, into: &result)
        }
        return result
    }

    private func collectEffectViews(in view: NSView, into result: inout [NSVisualEffectView]) {
        if let effectView = view as? NSVisualEffectView {
            result.append(effectView)
        }
        for child in view.subviews {
            collectEffectViews(in: child, into: &result)
        }
    }

    private func collectEffectViewKVO(in view: NSView) {
        if let effectView = view as? NSVisualEffectView {
            let observation = effectView.observe(
                \.state, options: [.new]
            ) { [weak effectView] _, change in
                MainActor.assumeIsolated {
                    guard let effectView,
                          let newState = change.newValue,
                          newState != .inactive else { return }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    effectView.state = .inactive
                    effectView.isHidden = true
                    CATransaction.commit()
                }
            }
            titlebarEffectKVOObservers.append(observation)
        }
        for child in view.subviews {
            collectEffectViewKVO(in: child)
        }
    }
}
