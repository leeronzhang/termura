import Foundation
import Network
import TermuraRemoteProtocol

actor LANConnection: ReplyChannel {
    nonisolated let channelId: UUID
    nonisolated let codec: any RemoteCodec
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var receiveTask: Task<Void, Never>?
    private var isOpen = false

    init(connection: NWConnection, codec: any RemoteCodec, channelId: UUID = UUID()) {
        self.channelId = channelId
        self.codec = codec
        self.connection = connection
        queue = DispatchQueue(label: "termura.remote.lan.\(channelId.uuidString.prefix(8))")
    }

    func start(handler: any EnvelopeHandler) {
        guard !isOpen else { return }
        isOpen = true
        connection.start(queue: queue)
        let id = channelId
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(handler: handler, channelId: id)
        }
    }

    func send(_ envelope: Envelope) async throws {
        guard isOpen else { throw TransportError.notRunning }
        let data = try codec.encode(envelope)
        try await sendData(data)
    }

    func close() async {
        guard isOpen else { return }
        isOpen = false
        receiveTask?.cancel()
        receiveTask = nil
        connection.cancel()
    }

    private func receiveLoop(handler: any EnvelopeHandler, channelId: UUID) async {
        while isOpen {
            do {
                let envelope = try await receiveOne()
                await handler.handle(envelope: envelope, replyChannel: self)
            } catch {
                break
            }
        }
        await handler.connectionClosed(channelId: channelId)
    }

    private func receiveOne() async throws -> Envelope {
        let codecRef = codec
        let nwConnection = connection
        return try await withCheckedThrowingContinuation { continuation in
            nwConnection.receiveMessage { content, _, _, error in
                if let error {
                    continuation.resume(throwing: TransportError.decodeFailure(reason: error.localizedDescription))
                    return
                }
                guard let data = content, !data.isEmpty else {
                    continuation.resume(throwing: TransportError.decodeFailure(reason: "empty frame"))
                    return
                }
                do {
                    let envelope = try codecRef.decode(Envelope.self, from: data)
                    continuation.resume(returning: envelope)
                } catch {
                    continuation.resume(throwing: TransportError.decodeFailure(reason: String(describing: error)))
                }
            }
        }
    }

    private func sendData(_ data: Data) async throws {
        let nwConnection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(identifier: "envelope", metadata: [metadata])
            nwConnection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: TransportError.sendFailure(reason: error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }
}
