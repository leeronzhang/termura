// Transcript file-read + JSONL parse helpers split out of
// `LiveAgentEventSource.swift` so the actor file stays under the
// file_length budget. Internal so this same-module extension can call
// `parser` (`ClaudeCodeTranscriptParser`) and back into actor state.

import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.app", category: "LiveAgentEventSource+Parsing")

extension LiveAgentEventSource {
    func readAppended(path: String, fromOffset offset: UInt64) -> Data? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        } catch {
            logger.warning("FileHandle open failed: \(error.localizedDescription)")
            return nil
        }
        defer {
            do {
                try handle.close()
            } catch {
                _ = error
            }
        }
        let data: Data
        do {
            try handle.seek(toOffset: offset)
            data = try handle.readToEnd() ?? Data()
        } catch {
            logger.warning("Transcript read failed: \(error.localizedDescription)")
            return nil
        }
        return data.isEmpty ? nil : data
    }

    func yieldParsed(
        _ data: Data,
        sessionId: UUID,
        into continuation: AsyncStream<AgentEvent>.Continuation
    ) {
        var seq: UInt64 = 0
        let allocator: () -> UInt64 = {
            seq += 1
            return seq
        }
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            do {
                let parsed = try parser.parseLine(
                    Data(line),
                    sessionId: sessionId,
                    seqAllocator: allocator
                )
                for event in parsed {
                    continuation.yield(event)
                }
            } catch {
                continue
            }
        }
    }

    func parseEvents(in data: Data, sessionId: UUID) -> [AgentEvent] {
        var seq: UInt64 = 0
        let allocator: () -> UInt64 = {
            seq += 1
            return seq
        }
        var events: [AgentEvent] = []
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            do {
                let parsed = try parser.parseLine(
                    Data(line),
                    sessionId: sessionId,
                    seqAllocator: allocator
                )
                events.append(contentsOf: parsed)
            } catch {
                continue
            }
        }
        return events
    }

    /// Apply the resume cursor or fall back to the most recent
    /// `tailCount` events for cold-start.
    func filteredEvents(
        _ all: [AgentEvent],
        sinceEventId: UUID?,
        tailCount: Int
    ) -> [AgentEvent] {
        if let sinceEventId,
           let idx = all.firstIndex(where: { $0.id == sinceEventId }) {
            return Array(all[(idx + 1)...])
        }
        return Array(all.suffix(tailCount))
    }
}
