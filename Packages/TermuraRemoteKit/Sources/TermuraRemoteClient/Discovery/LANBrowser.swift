import Foundation
import Network
import TermuraRemoteProtocol

public struct DiscoveredService: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let type: String
    /// Resolved Bonjour endpoint. Pass straight to
    /// `WebSocketClientTransport(nwEndpoint:)` so the client never has to
    /// know hostname or port — the listener may be on an ephemeral port and
    /// only NWBrowser knows the resolution.
    public let endpoint: NWEndpoint

    public init(id: String, name: String, type: String, endpoint: NWEndpoint) {
        self.id = id
        self.name = name
        self.type = type
        self.endpoint = endpoint
    }
}

extension DiscoveredService: Equatable {
    public static func == (lhs: DiscoveredService, rhs: DiscoveredService) -> Bool {
        // NWEndpoint isn't Equatable in older SDKs; identity is sufficient
        // since the Bonjour id encodes type + name uniquely per LAN.
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.type == rhs.type
    }
}

public actor LANBrowser {
    public typealias UpdateHandler = @Sendable ([DiscoveredService]) async -> Void

    private let serviceType: String
    private let queue: DispatchQueue
    private var browser: NWBrowser?
    private var current: [DiscoveredService] = []

    public init(serviceType: String = "_termura-remote._tcp") {
        self.serviceType = serviceType
        self.queue = DispatchQueue(label: "termura.remote.browser")
    }

    public func start(onChange: @escaping UpdateHandler) {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let parameters = NWParameters.tcp
        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            let services = results.compactMap { result -> DiscoveredService? in
                guard case let .service(name, type, _, _) = result.endpoint else { return nil }
                let identifier = "\(type)/\(name)"
                return DiscoveredService(
                    id: identifier,
                    name: name,
                    type: type,
                    endpoint: result.endpoint
                )
            }
            Task { await self?.publish(services: services, handler: onChange) }
        }
        newBrowser.start(queue: queue)
        browser = newBrowser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        current = []
    }

    public func currentServices() -> [DiscoveredService] {
        current
    }

    private func publish(services: [DiscoveredService], handler: UpdateHandler) async {
        current = services
        await handler(services)
    }
}
