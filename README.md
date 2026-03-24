# Termura

> Terminal UX, redesigned. Editor-grade input · Structured output · Knowledge persistence

A native macOS terminal built for power users of AI coding tools (Claude Code, Codex, Aider, etc.). No login required. Lightweight. Open Core.

## Why Termura

Traditional terminals dump thousands of lines of unstructured text. AI coding tools make this worse — massive diffs, long explanations, streaming output. Termura fixes this with three pillars:

- **Editor-grade Input** — NSTextView/TextKit 2 powered input with click-to-position cursor, multi-line editing, word-level navigation, and syntax highlighting
- **Structured Output** — Command output rendered as collapsible, independently scrollable blocks with one-click copy, instead of a wall of text
- **Knowledge Persistence** — Sessions auto-saved with full-text search, integrated Markdown notes, and token usage tracking

## Features

- Native macOS app (SwiftUI + AppKit), targeting macOS 14+
- Multi-session management with sidebar navigation
- Visor mode (global hotkey drop-down terminal)
- Shell integration via OSC 133 protocol
- Themeable with a design token system
- GRDB-backed local storage (`~/.termura/`)
- Zero telemetry, zero login, fully offline

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI + AppKit |
| Terminal | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) |
| Syntax Highlighting | [Highlightr](https://github.com/raspu/Highlightr) |
| Database | [GRDB](https://github.com/groue/GRDB.swift) |
| Shortcuts | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) |
| Build | XcodeGen + Swift 6.0 |

## Getting Started

### Requirements

- macOS 14.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build

```bash
# Generate Xcode project
xcodegen generate

# Build
xcodebuild -scheme Termura -configuration Debug build
```

### Development

```bash
# Lint
swiftlint lint --strict

# Format
swiftformat Sources/ --verbose
```

## Roadmap

| Phase | Focus |
|-------|-------|
| **Phase 1** | Basic terminal, sidebar, multi-session, visor mode, theming |
| **Phase 2** | Shell integration (OSC 133), editor input, output chunking, token tracking |
| **Phase 3** | Markdown notes, session persistence & search, sidebar enhancements |
| **Phase 4** | Session timeline, interactive elements, background monitoring, theme engine |

## Contributing

Contributions are welcome! Please read the project guidelines before submitting a PR.

## License

[Apache License 2.0](LICENSE) — see [LICENSE](LICENSE) for details.
