import Foundation

extension Duration {
    /// Converts a `Duration` value to a `Double` representing seconds.
    ///
    /// `Duration.components` exposes `(seconds: Int64, attoseconds: Int64)`.
    /// Attoseconds are 1e-18 seconds, so the full conversion is:
    ///   seconds + attoseconds / 1e18
    ///
    /// This property centralises the conversion that previously appeared inline
    /// across DatabaseService, SearchService, SessionStore, SwiftTermEngine, and AppDelegate.
    var totalSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
