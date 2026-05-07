import CloudKit
import Foundation
import TermuraRemoteProtocol
import Testing

/// Real-iCloud integration tests for `LiveCloudKitDatabaseGateway`. Lives in
/// `TermuraTests` (the Mac app host bundle) rather than the SPM
/// `TermuraRemoteProtocolTests` target because pure `swift test` runs
/// without an embedded provisioning profile, and `CKContainer(identifier:)`
/// then SIGTRAPs immediately on a missing iCloud entitlement. The Mac
/// app's xctest bundle inherits `Resources/Termura.entitlements`, which
/// declares `iCloud.com.termura.remote`, so CKContainer construction is
/// allowed. The static-helper unit tests for `isMissingRecordType` /
/// `mapFetchError` live alongside `LiveCloudKitGatewayTests` in the SPM
/// package — those don't need a real container.
///
/// Disabled by default. To run locally:
///
///     TERMURA_LIVE_CLOUDKIT=1 \
///     xcodebuild test \
///       -project Termura.xcodeproj \
///       -scheme Termura -destination 'platform=macOS' \
///       -only-testing:TermuraTests/LiveCloudKitGatewayIntegrationTests
///
/// Why this suite exists: the rest of the test surface uses
/// `InMemoryCloudKitDatabaseGateway`, so the production CKContainer
/// codepath was never exercised by a green CI run. CLAUDE.md §8.3 calls
/// this out as the mock-drift trap — and that's exactly what bit users
/// when iOS pair against a real account hit "Permission Failure" /
/// "Did not find record type" while the in-memory tests stayed green.
/// This suite makes that gap visible.
@Suite("LiveCloudKitDatabaseGateway live integration",
       .enabled(if: ProcessInfo.processInfo.environment["TERMURA_LIVE_CLOUDKIT"] != nil,
                "Set TERMURA_LIVE_CLOUDKIT=1 with an iCloud account signed in"))
struct LiveCloudKitGatewayIntegrationTests {
    private static let containerId = "iCloud.com.termura.remote"
    private static let testTargetId = UUID()
    private static let testSourceId = UUID()

    /// Round-trip a single envelope record through the real container. If
    /// schema/index/permission state is wrong this fails with the CKError
    /// surface the user actually sees in the app.
    @Test("save → fetch → delete round-trip")
    func liveRoundTrip() async throws {
        let gateway = LiveCloudKitDatabaseGateway(containerIdentifier: Self.containerId)
        let recordId = "live-rt-\(UUID().uuidString)"
        let now = Date()
        let envelope = Envelope(kind: .ping, payload: Data())
        let record = CloudKitEnvelopeRecord(
            id: recordId,
            payload: .plaintext(envelope),
            targetDeviceId: Self.testTargetId,
            sourceDeviceId: Self.testSourceId,
            createdAt: now,
            schemaVersion: CloudKitSchema.currentSchemaVersion
        )

        try await gateway.save(record)
        defer {
            // Best-effort cleanup so re-runs don't leak orphan records.
            // The defer is sync so we wrap the async delete in a Task;
            // failure here is logged-only — the test has already asserted
            // what matters and a failed delete shouldn't mask the result.
            Task {
                do {
                    try await gateway.delete(id: recordId)
                } catch {
                    print("[LiveCloudKitGatewayIntegrationTests] cleanup delete failed (Non-critical): \(error)")
                }
            }
        }

        let fetched = try await gateway.fetch(
            targetDeviceId: Self.testTargetId,
            since: now.addingTimeInterval(-60)
        )
        let match = fetched.records.first { $0.id == recordId }
        #expect(match != nil, "Just-saved record should be visible to fetch")

        try await gateway.delete(id: recordId)
        let afterDelete = try await gateway.fetch(
            targetDeviceId: Self.testTargetId,
            since: now.addingTimeInterval(-60)
        )
        #expect(!afterDelete.records.contains { $0.id == recordId },
                "Deleted record must not appear in subsequent fetch")
    }

    /// Fetch on a target with no records — verifies the cold-start short
    /// circuit (`isMissingRecordType` → `[]`) and/or the normal empty
    /// query result both surface as `[]`. If a freshly-provisioned
    /// container surfaces "Permission Failure" or any other CKError, this
    /// test fails — and that's the exact production symptom we want to
    /// catch before shipping.
    @Test("fetch on never-touched target returns []")
    func liveFetchEmptyTarget() async throws {
        let gateway = LiveCloudKitDatabaseGateway(containerIdentifier: Self.containerId)
        let untouchedTarget = UUID()
        let fetched = try await gateway.fetch(
            targetDeviceId: untouchedTarget,
            since: .distantPast
        )
        #expect(fetched.records.isEmpty)
        #expect(fetched.quarantined.isEmpty)
    }

    /// Pin the *shape* of the error a non-existent container surfaces, so
    /// later changes to error mapping don't silently hide it. We expect a
    /// `CloudKitGatewayError` of some flavour — the typed enum is the
    /// stable contract; the `reason` string is best-effort. If the
    /// mapping changes (e.g. starts swallowing the error), this fails
    /// and forces an explicit decision rather than letting the user see
    /// a silent hang.
    @Test("save against bad container surfaces CloudKitGatewayError")
    func liveBadContainerSurfacesReason() async throws {
        let gateway = LiveCloudKitDatabaseGateway(
            containerIdentifier: "iCloud.com.termura.does-not-exist-\(UUID().uuidString)"
        )
        let now = Date()
        let envelope = Envelope(kind: .ping, payload: Data())
        let record = CloudKitEnvelopeRecord(
            id: "x-\(UUID().uuidString)",
            payload: .plaintext(envelope),
            targetDeviceId: Self.testTargetId,
            sourceDeviceId: Self.testSourceId,
            createdAt: now,
            schemaVersion: CloudKitSchema.currentSchemaVersion
        )
        await #expect(throws: CloudKitGatewayError.self) {
            try await gateway.save(record)
        }
    }
}
