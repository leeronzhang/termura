import Combine
import Foundation

protocol NotificationCenterObserving: AnyObject, Sendable {
    func addObserver(
        forName name: NSNotification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol

    func removeObserver(_ observer: Any)

    func addObserver(
        _ observer: Any,
        selector aSelector: Selector,
        name aName: NSNotification.Name?,
        object anObject: Any?
    )

    func publisher(
        for name: Notification.Name,
        object: AnyObject?
    ) -> NotificationCenter.Publisher
}

extension NotificationCenterObserving {
    func publisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        publisher(for: name, object: nil)
    }
}

extension NotificationCenter: NotificationCenterObserving {}
