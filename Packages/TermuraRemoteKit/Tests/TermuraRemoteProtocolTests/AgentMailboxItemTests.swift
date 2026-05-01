import Foundation
@testable import TermuraRemoteProtocol
import Testing

@Suite("AgentMailboxItem wire shape")
struct AgentMailboxItemTests {
    private static func sample(
        kind: AgentMailboxItem.PayloadKind = .plaintext,
        payloadData: Data = Data([0xAB, 0xCD])
    ) -> AgentMailboxItem {
        AgentMailboxItem(
            recordName: "RECORD-1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceDeviceId: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            payloadKind: kind,
            payloadData: payloadData
        )
    }

    @Test("Codable round-trip preserves every field")
    func roundTrip() throws {
        let original = Self.sample()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentMailboxItem.self, from: data)
        #expect(decoded == original)
        #expect(decoded.schemaVersion == AgentMailboxItem.currentSchemaVersion)
    }

    @Test("plaintext payload contract: recordName + createdAt domains stay separate")
    func plaintextDomainsStaySeparate() {
        let item = Self.sample(kind: .plaintext)
        // recordName is for delete addressing / quarantine key only.
        // createdAt is the cursor-advance source of truth.
        #expect(item.recordName == "RECORD-1")
        #expect(item.createdAt.timeIntervalSince1970 == 1_700_000_000)
    }

    @Test("cipher and plaintext payload kinds are distinct on the wire")
    func payloadKindIsExplicit() throws {
        let plaintext = Self.sample(kind: .plaintext)
        let cipher = Self.sample(kind: .cipher)
        let plainData = try JSONEncoder().encode(plaintext)
        let cipherData = try JSONEncoder().encode(cipher)
        #expect(plainData != cipherData)
    }

    @Test("schemaVersion default matches currentSchemaVersion")
    func defaultSchemaVersion() {
        let item = Self.sample()
        #expect(item.schemaVersion == AgentMailboxItem.currentSchemaVersion)
    }
}
