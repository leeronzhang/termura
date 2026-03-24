import Foundation

/// Pure value type command history with circular buffer and bidirectional navigation.
/// No AppKit or UI imports — fully testable in isolation.
struct InputHistory {
    // MARK: - Storage

    private let capacity: Int
    private var buffer: [String]
    /// Index where the next write will land.
    private var writeHead: Int
    /// Count of valid entries stored.
    private var count: Int
    /// Navigation cursor; -1 means "at present" (not browsing history).
    private var cursor: Int
    private var isEmpty: Bool { count == 0 }

    // MARK: - Init

    init(capacity: Int = AppConfig.Input.historyCapacity) {
        self.capacity = max(1, capacity)
        buffer = Array(repeating: "", count: self.capacity)
        writeHead = 0
        count = 0
        cursor = -1
    }

    // MARK: - Public API

    /// Push a new entry. Empty strings are silently ignored. Resets navigation cursor.
    mutating func push(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        buffer[writeHead] = trimmed
        writeHead = (writeHead + 1) % capacity
        count = min(count + 1, capacity)
        cursor = -1
    }

    /// Navigate to older entries. Returns the entry or nil if history is empty.
    mutating func navigatePrevious() -> String? {
        guard !isEmpty else { return nil }
        if cursor == -1 {
            cursor = 0
        } else if cursor < count - 1 {
            cursor += 1
        }
        return entry(at: cursor)
    }

    /// Navigate to newer entries. Returns the entry, or nil when back at present.
    mutating func navigateNext() -> String? {
        guard cursor > 0 else {
            cursor = -1
            return nil
        }
        cursor -= 1
        return entry(at: cursor)
    }

    /// Reset navigation cursor to "present" without modifying the buffer.
    mutating func resetCursor() {
        cursor = -1
    }

    // MARK: - Private helpers

    /// Return the entry at logical offset `offset` (0 = most recent).
    private func entry(at offset: Int) -> String {
        let index = (writeHead - 1 - offset + capacity * 2) % capacity
        return buffer[index]
    }
}
