// PR8 Phase 2 — `termura-remote-agent` entry point. Constructs the
// live `AgentLifecycle`, runs until SIGTERM/SIGINT, and lets the
// top-level script fall through to a normal process exit (status 0).
// All real work lives in lifecycle subsystems; main.swift is the
// composition root only.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.remote-agent", category: "main")

logger.info("LaunchAgent starting, pid=\(getpid())")
let lifecycle = await MainActor.run { AgentLifecycle.makeLive() }
await MainActor.run { AgentLifecycle.shared = lifecycle }
await lifecycle.run()
logger.info("LaunchAgent exiting cleanly")
