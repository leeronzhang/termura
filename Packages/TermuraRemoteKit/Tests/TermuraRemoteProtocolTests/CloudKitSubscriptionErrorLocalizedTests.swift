import Foundation
@testable import TermuraRemoteProtocol
import Testing

@Suite("CloudKitSubscriptionError LocalizedError")
struct CloudKitSubscriptionErrorLocalizedTests {
    /// Regression: pre-fix, the Mac Settings toggle surfaced
    /// "The operation couldn't be completed.
    /// (TermuraRemoteProtocol.CloudKitSubscriptionError error 0.)" because
    /// the enum lacked LocalizedError conformance and Foundation fell back
    /// to its NSError-shaped default. Pinning the format here so the
    /// underlying CKError reason can't be hidden again.
    @Test("backingFailure carries reason into localizedDescription")
    func backingFailureCarriesReason() {
        let err: any Error = CloudKitSubscriptionError.backingFailure(reason: "Permission Failure")
        #expect(err.localizedDescription == "CloudKit subscription failed: Permission Failure")
    }
}
