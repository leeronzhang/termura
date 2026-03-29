import AppKit
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "MenuBarService")

/// Manages the app's NSStatusItem to display a failure-count badge
/// and provide a click target to bring the main window forward.
@MainActor
final class MenuBarService: NSObject {
    private var statusItem: NSStatusItem?
    private var failureCount = 0
    private var onActivateHandler: (() -> Void)?

    override init() {
        super.init()
        setupStatusItem()
    }

    func configure(onActivate: @escaping () -> Void) {
        onActivateHandler = onActivate
    }

    func recordFailure() {
        failureCount += 1
        updateBadge()
    }

    func clearBadge() {
        failureCount = 0
        updateBadge()
    }

    // MARK: - Private

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: "Termura")
        icon?.isTemplate = true
        // Scale down to 14pt height while preserving the original 27:16 aspect ratio.
        icon?.size = NSSize(width: 20.25, height: 12)
        button.image = icon
        button.target = self
        button.action = #selector(handleClick)
    }

    private func updateBadge() {
        guard let button = statusItem?.button else { return }
        button.title = failureCount > 0 ? " \(failureCount)" : ""
    }

    @objc private func handleClick() {
        clearBadge()
        NSApp.activate(ignoringOtherApps: true)
        onActivateHandler?()
    }
}
