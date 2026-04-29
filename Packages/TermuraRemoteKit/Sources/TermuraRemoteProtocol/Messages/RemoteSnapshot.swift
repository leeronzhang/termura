import Foundation

public struct RemoteSnapshot: Sendable, Codable, Equatable {
    public let commandId: UUID
    public let sessionId: UUID
    public let stdout: String
    public let attachmentRef: SnapshotAttachmentRef?
    public let exitCode: Int32?
    public let truncated: Bool
    public let producedAt: Date

    public init(
        commandId: UUID,
        sessionId: UUID,
        stdout: String,
        attachmentRef: SnapshotAttachmentRef? = nil,
        exitCode: Int32? = nil,
        truncated: Bool = false,
        producedAt: Date = Date()
    ) {
        self.commandId = commandId
        self.sessionId = sessionId
        self.stdout = stdout
        self.attachmentRef = attachmentRef
        self.exitCode = exitCode
        self.truncated = truncated
        self.producedAt = producedAt
    }
}

public struct SessionDescriptor: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let title: String
    public let workingDirectory: String?
    public let lastActivityAt: Date

    public init(id: UUID, title: String, workingDirectory: String?, lastActivityAt: Date) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.lastActivityAt = lastActivityAt
    }
}

public struct SessionListPayload: Sendable, Codable, Equatable {
    public let sessions: [SessionDescriptor]
    public let producedAt: Date

    public init(sessions: [SessionDescriptor], producedAt: Date = Date()) {
        self.sessions = sessions
        self.producedAt = producedAt
    }
}
