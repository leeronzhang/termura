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

    /// Regression: a Production-signed Mac (archive build) cannot
    /// auto-create the `RemoteEnvelope` record type. Previously the
    /// schema-bootstrap save's failure leaked `recordName=…schema-
    /// bootstrap` and a raw "Cannot create new type … in production
    /// schema" string to the toggle. The typed `.schemaNotDeployed`
    /// case now owns that surface and points the operator at the
    /// CloudKit Dashboard / Debug-build escape hatch.
    @Test("schemaNotDeployed surfaces an actionable instruction")
    func schemaNotDeployedDescribesAction() {
        let err: any Error = CloudKitSubscriptionError.schemaNotDeployed
        let description = err.localizedDescription
        #expect(description.contains("RemoteEnvelope record type is not deployed"))
        #expect(description.contains("CloudKit Dashboard"))
        #expect(description.contains("Debug-signed build"))
        // Internal-implementation details must not appear in the user-
        // visible message — those are what the pre-fix surface leaked.
        #expect(!description.contains("schema-bootstrap"))
        #expect(!description.contains("recordName"))
    }
}
