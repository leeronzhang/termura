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

/// Browser state surfaced through `LANBrowser.start`'s `onState` hook so
/// callers can drive UI when NWBrowser fails or is waiting for the OS to
/// recover (e.g. Local Network permission has not been granted).
public enum LANBrowserState: Sendable, Equatable {
    case idle
    case browsing
    /// Transient: NWBrowser is parked while the OS arbitrates connectivity.
    /// Most often surfaces when Local Network permission is denied —
    /// `Privacy & Security → Local Network` has revoked the entitlement.
    case waiting(reason: String)
    /// Terminal NWBrowser failure. UI must offer a recovery action
    /// (open Settings, retry) instead of a forever-spinner.
    case failed(reason: String)
    case cancelled
}

public actor LANBrowser {
    public typealias UpdateHandler = @Sendable ([DiscoveredService]) async -> Void
    public typealias StateHandler = @Sendable (LANBrowserState) async -> Void

    private let serviceType: String
    private let queue: DispatchQueue
    private var browser: NWBrowser?
    private var current: [DiscoveredService] = []
    private var lastState: LANBrowserState = .idle

    public init(serviceType: String = "_termura-remote._tcp") {
        self.serviceType = serviceType
        queue = DispatchQueue(label: "termura.remote.browser")
    }

    public func start(
        onChange: @escaping UpdateHandler,
        onState: @escaping StateHandler = { _ in }
    ) {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let parameters = NWParameters.tcp
        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.stateUpdateHandler = { [weak self] state in
            let mapped = LANBrowser.map(nwState: state)
            Task { await self?.publishState(mapped, handler: onState) }
        }
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
        lastState = .idle
    }

    public func currentServices() -> [DiscoveredService] {
        current
    }

    public func currentState() -> LANBrowserState {
        lastState
    }

    /// Pure mapping from `NWBrowser.State` to the public `LANBrowserState`,
    /// extracted so unit tests can pin the state-translation contract without
    /// instantiating an NWBrowser.
    public static func map(nwState: NWBrowser.State) -> LANBrowserState {
        switch nwState {
        case .setup:
            .idle
        case .ready:
            .browsing
        case let .waiting(error):
            .waiting(reason: error.localizedDescription)
        case let .failed(error):
            .failed(reason: error.localizedDescription)
        case .cancelled:
            .cancelled
        @unknown default:
            .idle
        }
    }

    private func publish(services: [DiscoveredService], handler: UpdateHandler) async {
        current = services
        await handler(services)
    }

    private func publishState(_ state: LANBrowserState, handler: StateHandler) async {
        lastState = state
        await handler(state)
    }
}
