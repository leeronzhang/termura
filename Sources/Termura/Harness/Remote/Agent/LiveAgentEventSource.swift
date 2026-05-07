// Wave 8 — paid-side `AgentEventSource` implementation.
//
// On `subscribe(...)`:
//   1. Resolves the Termura session's working directory through the
//      caller-supplied resolver, then finds the most recently-mtime'd
//      Claude Code transcript JSONL via `TranscriptResolver`.
//   2. Reads the whole file once, parses it line-by-line, and ships
//      the most recent N events as the cold-start
//      `AgentEventCheckpoint`.
//   3. Spins a per-subscription `Task` that polls the transcript
//      file every `pollingInterval`; when the byte length grows, the
//      poller reads the appended slice, parses each newline-delimited
//      JSON line, and yields the resulting `AgentEvent`s into the
//      caller's `AsyncStream`.
//
// **Why polling, not DispatchSource**: a prior iteration used a
// `DispatchSourceFileSystemObject` over the transcript fd. Field
// testing showed that path is unreliable as Claude Code's writer
// pattern (buffered fwrite with infrequent flushes, occasional
// atomic rename) makes `.extend` events arrive late or never. A
// once-per-second `stat` syscall is the most stable POSIX primitive
// available; sub-second latency is not a product requirement (chat
// is read by humans), but "iOS sees the message at all" is.
//
// Lifecycle (§4.2):
//   * **OWNER**: per-subscription `pollerTask` stored in
//     `subscriptions[subscriptionId]`.
//   * **CANCEL**: `unsubscribe(sessionId:subscriptionId:)` cancels
//     the task and finishes the stream continuation.
//   * **TEARDOWN**: actor deallocation drops the dict entries; the
//     poller task captures `[weak self]` so the loop exits when the
//     source is collected.
//   * **TEST**: parser logic covered by
//     `ClaudeCodeTranscriptParserTests`; polling IO is platform code,
//     validated via manual QA against a real Claude Code session.
//
// **Limitation**: a Claude Code restart writes a *new* `.jsonl` in
// the same project directory. The poller still watches the path
// resolved at subscribe time and won't follow the new file; the iOS
// client picks up the new transcript automatically on its next
// subscribe (scenePhase active, or the user navigating back into
// the session).

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "LiveAgentEventSource")

/// Most recent N events shipped in the cold-start checkpoint. Bounded
/// so a multi-hour Claude Code session doesn't dump tens of thousands
/// of events at iOS subscribe time.
private let coldStartEventCount: Int = 50

actor LiveAgentEventSource: AgentEventSource {
    private let cwdResolver: @MainActor @Sendable (UUID) -> String?
    private let clock: @Sendable () -> Date
    private let pollingInterval: Duration
    let parser = ClaudeCodeTranscriptParser()
    var subscriptions: [UUID: SubscriptionEntry] = [:]

    struct SubscriptionEntry {
        let pollerTask: Task<Void, Never>
        let continuation: AsyncStream<AgentEvent>.Continuation
        let sessionId: UUID
        let path: String
        var lastReadOffset: UInt64
    }

    init(
        cwdResolver: @escaping @MainActor @Sendable (UUID) -> String?,
        clock: @escaping @Sendable () -> Date = { Date() },
        pollingInterval: Duration = .seconds(1)
    ) {
        self.cwdResolver = cwdResolver
        self.clock = clock
        self.pollingInterval = pollingInterval
    }

    func subscribe(
        sessionId: UUID,
        sinceEventId: UUID?
    ) async -> AgentEventSubscription? {
        let cwdResolverCopy = cwdResolver
        let cwd = await MainActor.run { cwdResolverCopy(sessionId) }
        guard let cwd else {
            logger.info("Agent subscribe: no cwd for session \(sessionId)")
            return nil
        }
        guard let path = TranscriptResolver.latestTranscriptPath(forCwd: cwd) else {
            logger.info("Agent subscribe: no transcript at \(cwd, privacy: .public)")
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            logger.warning("Failed reading \(path, privacy: .public): \(error.localizedDescription)")
            return nil
        }
        let allEvents = parseEvents(in: data, sessionId: sessionId)
        let coldEvents = filteredEvents(allEvents, sinceEventId: sinceEventId, tailCount: coldStartEventCount)
        let checkpoint = AgentEventCheckpoint(sessionId: sessionId, events: coldEvents, producedAt: clock())
        return registerSubscription(
            sessionId: sessionId,
            path: path,
            initialOffset: UInt64(data.count),
            checkpoint: checkpoint
        )
    }

    /// Build the subscription handle, spawn the polling task, and
    /// store the entry so `unsubscribe(...)` can tear it down.
    private func registerSubscription(
        sessionId: UUID,
        path: String,
        initialOffset: UInt64,
        checkpoint: AgentEventCheckpoint
    ) -> AgentEventSubscription {
        let (stream, continuation) = AsyncStream<AgentEvent>.makeStream()
        let subscriptionId = UUID()
        let pollerTask: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await runPollLoop(sessionId: sessionId, subscriptionId: subscriptionId)
        }
        subscriptions[subscriptionId] = SubscriptionEntry(
            pollerTask: pollerTask,
            continuation: continuation,
            sessionId: sessionId,
            path: path,
            lastReadOffset: initialOffset
        )
        logger.info("Agent subscribe: poller started session=\(sessionId) path=\(path, privacy: .public)")
        return AgentEventSubscription(
            id: subscriptionId,
            checkpoint: checkpoint,
            stream: stream
        )
    }

    func unsubscribe(sessionId _: UUID, subscriptionId: UUID) async {
        guard let entry = subscriptions.removeValue(forKey: subscriptionId) else { return }
        entry.pollerTask.cancel()
        entry.continuation.finish()
    }

    /// Per-subscription poller. Sleeps `pollingInterval`, then calls
    /// `pollOnce`. Exits cleanly on cancellation or when the entry
    /// has been removed (e.g. after `unsubscribe`).
    private func runPollLoop(sessionId: UUID, subscriptionId: UUID) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: pollingInterval)
            } catch is CancellationError {
                // CancellationError is expected — `unsubscribe(...)` cancels
                // the poller task on tear-down; exit cleanly.
                return
            } catch {
                return
            }
            if subscriptions[subscriptionId] == nil { return }
            await pollOnce(sessionId: sessionId, subscriptionId: subscriptionId)
        }
    }

    /// Single tick: stat the transcript, read any newly-appended
    /// bytes, parse each newline-delimited JSON line, and yield the
    /// resulting events into the subscription's stream. Returns
    /// silently when nothing new is available.
    private func pollOnce(sessionId: UUID, subscriptionId: UUID) async {
        guard var entry = subscriptions[subscriptionId] else { return }
        let size: UInt64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: entry.path)
            guard let measured = attrs[.size] as? UInt64 else { return }
            size = measured
        } catch {
            logger.warning("Stat failed for \(entry.path, privacy: .public): \(error.localizedDescription)")
            return
        }
        if size < entry.lastReadOffset {
            // File replaced / truncated. Reset to the new size so we
            // do not re-emit the prefix that may overlap; the next
            // tick will pick up subsequent appends.
            entry.lastReadOffset = size
            subscriptions[subscriptionId] = entry
            return
        }
        if size == entry.lastReadOffset { return }
        guard let appended = readAppended(path: entry.path, fromOffset: entry.lastReadOffset) else { return }
        entry.lastReadOffset += UInt64(appended.count)
        subscriptions[subscriptionId] = entry
        yieldParsed(appended, sessionId: sessionId, into: entry.continuation)
    }
}
