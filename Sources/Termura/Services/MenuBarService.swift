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
        button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Termura")
        button.target = self
        button.action = #selector(handleClick)
    }

    private func updateBadge() {
        guard let button = statusItem?.button else { return }
        button.title = failureCount > 0 ? " \(failureCount)" : ""
    }

    @objc private func handleClick() {
        NSApp.activate(ignoringOtherApps: true)
        onActivateHandler?()
    }
}
