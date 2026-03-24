import Foundation

/// Desktop notification triggered by OSC 9.
enum OSC9Event: Sendable, Equatable {
    case notify(message: String)
}

/// Progress reporting triggered by OSC 99 (ConEmu-style).
/// `state`: 0 = hide, 1 = normal, 2 = error, 3 = indeterminate, 4 = paused.
enum OSC99Event: Sendable, Equatable {
    case progress(state: Int, value: Int?)
}

/// Rich notification triggered by OSC 777 (rxvt-unicode-style).
enum OSC777Event: Sendable, Equatable {
    case notification(title: String, body: String)
}

/// Stateless parsers for OSC 9, 99, and 777 payloads.
/// Follows the same pattern as `OSC133Parser`.
enum OSCExtendedParser {
    // MARK: - OSC 9: Growl-style notification

    static func parseOSC9(_ payload: ArraySlice<UInt8>) -> OSC9Event? {
        guard !payload.isEmpty else { return nil }
        guard let message = String(bytes: payload, encoding: .utf8),
              !message.isEmpty else { return nil }
        return .notify(message: message)
    }

    // MARK: - OSC 99: Progress (state[;value])

    static func parseOSC99(_ payload: ArraySlice<UInt8>) -> OSC99Event? {
        guard !payload.isEmpty else { return nil }
        guard let raw = String(bytes: payload, encoding: .utf8) else { return nil }
        let parts = raw.split(separator: ";", maxSplits: 2)
        guard let first = parts.first, let state = Int(first) else { return nil }
        let value: Int? = parts.count > 1 ? Int(parts[1]) : nil
        return .progress(state: state, value: value)
    }

    // MARK: - OSC 777: notify;title;body

    static func parseOSC777(_ payload: ArraySlice<UInt8>) -> OSC777Event? {
        guard !payload.isEmpty else { return nil }
        guard let raw = String(bytes: payload, encoding: .utf8) else { return nil }
        let parts = raw.split(separator: ";", maxSplits: 3)
        // Expected: ["notify", title, body]
        guard parts.count >= 3,
              parts[0] == "notify" else { return nil }
        let title = String(parts[1])
        let body = String(parts[2])
        return .notification(title: title, body: body)
    }
}
