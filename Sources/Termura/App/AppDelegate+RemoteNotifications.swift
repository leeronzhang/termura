import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AppDelegate.Push")

// CloudKit silent-push hooks. Registered via `NSApp.registerForRemoteNotifications()`
// in `applicationDidFinishLaunching`. The `didReceiveRemoteNotification` route
// hands off to `services.remoteIntegration.notifyPushReceived()`, which the
// active `RemoteIntegration` implementation forwards to its remote-control
// transport so the inbox is polled immediately instead of waiting for the
// next interval tick.
extension AppDelegate {
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        let integration = services.remoteIntegration
        Task { await integration.notifyPushReceived() }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Registered for remote notifications, token bytes=\(deviceToken.count)")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        logger.warning("Remote notification registration failed: \(error.localizedDescription)")
    }
}
