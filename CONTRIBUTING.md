# Contributing to Termura

## Using Termura

Download the latest release from the [Releases](https://github.com/leeronzhang/termura/releases) page. No build setup required.

## Reporting Issues

Found a bug or have a feature request? Please [open an issue](https://github.com/leeronzhang/termura/issues) with:

- macOS version
- Termura version
- Steps to reproduce (for bugs)
- Expected vs actual behavior

## Reading the Source

The source code is available for reference and review. The project is built with:

- **SwiftUI + AppKit** — UI layer
- **libghostty** (vendored as a submodule + xcframework) — Metal GPU-accelerated terminal emulation
- **GRDB** — local session storage (SQLite + FTS5)
- **Highlightr** — syntax highlighting
- **KeyboardShortcuts** — global hotkeys
- **TermuraRemoteKit** (in-tree SPM package) — wire protocol + LAN/CloudKit transports for the iOS Remote companion
- **AgentXPCInterfaces** + **LaunchAgent** (in-tree SPM packages) — XPC bridge + daemon helper for cross-network remote control

For the engineering policy that all PRs must conform to, see [CLAUDE.md](CLAUDE.md).

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
