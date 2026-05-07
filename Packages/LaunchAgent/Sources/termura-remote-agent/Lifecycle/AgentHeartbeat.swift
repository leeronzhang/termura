// PR8 Phase 2 — minimal liveness heartbeat. Independent task that
// emits an OSLog `debug` line every 5 minutes so launchd's runtime
// view of the agent stays warm and ops have a coarse activity
// signal.
//
// OWNER: this actor (lifetime tied to AgentLifecycle)
// CANCEL: AgentLifecycle.requestStop -> heartbeat.cancel()
// TEARDOWN: cancellation breaks the sleep; loop returns

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.remote-agent", category: "AgentHeartbeat")

actor AgentHeartbeat {
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(interval: Duration = .seconds(300)) {
        self.interval = interval
    }

    func start() {
        guard task == nil else { return }
        task = Task { [interval] in
            while !Task.isCancelled {
                logger.debug("agent heartbeat")
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
