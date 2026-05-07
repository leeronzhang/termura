// `QuarantineState` + `QuarantineEntry` model split out of
// `AgentQuarantineStore.swift` so the actor file stays under the
// file_length budget. The store, dispatcher, and any future
// administrative tooling all read these as the canonical wire model.

import Foundation

enum QuarantineState: String, Sendable, Codable, Equatable {
    case retrying
    case quarantined
}

struct QuarantineEntry: Sendable, Codable, Equatable {
    let recordName: String
    let createdAt: Date
    let reasonCode: String
    let attempts: Int
    let firstSeenAt: Date
    let state: QuarantineState

    private enum CodingKeys: String, CodingKey {
        case recordName, createdAt, reasonCode, attempts, firstSeenAt, state
    }

    init(
        recordName: String,
        createdAt: Date,
        reasonCode: String,
        attempts: Int,
        firstSeenAt: Date,
        state: QuarantineState
    ) {
        self.recordName = recordName
        self.createdAt = createdAt
        self.reasonCode = reasonCode
        self.attempts = attempts
        self.firstSeenAt = firstSeenAt
        self.state = state
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordName = try container.decode(String.self, forKey: .recordName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        reasonCode = try container.decode(String.self, forKey: .reasonCode)
        attempts = try container.decode(Int.self, forKey: .attempts)
        firstSeenAt = try container.decode(Date.self, forKey: .firstSeenAt)
        // Pre-PR8.2 entries were always quarantined (the file did not
        // distinguish states). Default missing field to `.quarantined`
        // so existing on-disk data keeps its previous filtering
        // behaviour rather than silently re-injecting old failures.
        state = try container.decodeIfPresent(QuarantineState.self, forKey: .state) ?? .quarantined
    }
}
