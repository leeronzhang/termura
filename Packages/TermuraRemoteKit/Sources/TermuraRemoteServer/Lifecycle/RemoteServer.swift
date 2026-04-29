import Foundation
import TermuraRemoteProtocol

public actor RemoteServer {
    public enum State: Sendable, Equatable {
        case stopped
        case starting
        case running
        case stopping
    }

    private let transports: [any RemoteTransport]
    private let handler: any EnvelopeHandler
    private(set) public var state: State = .stopped

    public init(transports: [any RemoteTransport], handler: any EnvelopeHandler) {
        self.transports = transports
        self.handler = handler
    }

    public func start() async throws {
        guard state == .stopped else {
            throw RemoteServerError.invalidStateTransition(from: state, requested: .running)
        }
        state = .starting
        do {
            for transport in transports {
                try await transport.start(handler: handler)
            }
        } catch {
            await rollbackStart()
            state = .stopped
            throw error
        }
        state = .running
    }

    public func stop() async {
        guard state == .running || state == .starting else { return }
        state = .stopping
        for transport in transports {
            await transport.stop()
        }
        state = .stopped
    }

    public func transportNames() -> [String] {
        transports.map { $0.name }
    }

    private func rollbackStart() async {
        for transport in transports {
            await transport.stop()
        }
    }
}

public enum RemoteServerError: Error, Sendable, Equatable {
    case invalidStateTransition(from: RemoteServer.State, requested: RemoteServer.State)
}
