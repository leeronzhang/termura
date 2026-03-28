# Contributing to Termura

Thank you for your interest in contributing! This document covers how to get started, the development workflow, and the quality standards all contributions must meet.

## Getting Started

### Prerequisites

- macOS 14.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- SwiftLint: `brew install swiftlint`
- SwiftFormat: `brew install swiftformat`

### Setup

```bash
git clone https://github.com/leeronzhang/termura.git
cd termura

# Install dev tools and pre-commit hook
make setup

# Generate Xcode project
make gen

# Open in Xcode
open Termura.xcodeproj
```

## Development Workflow

```bash
make lint          # SwiftLint strict check
make format        # Auto-format with SwiftFormat
make build         # Debug build
make test          # Run all tests
make contract-test # Run contract tests (Mock vs Real consistency)
make ci-local      # Full local CI simulation before pushing
```

## Pre-commit Hook

`make setup` installs a pre-commit hook that checks:

- SwiftLint (strict)
- Force unwrap / `try!` / `as!` detection
- `fatalError` in production code
- Legacy `DispatchQueue` usage
- `try?` error suppression
- File size limit (300 lines)
- Protocol/Mock pairing completeness

Fix all errors before committing. Warnings are advisory.

## Code Quality Requirements

All contributions must adhere to the standards in the architecture:

**Concurrency**
- Use `async/await` and structured concurrency throughout
- No `DispatchQueue.main.async` — use `Task { @MainActor in ... }` instead
- No `DispatchQueue.global()` — use `Task.detached`

**Safety**
- Zero force unwraps: no `!`, `try!`, or `as!`
- Zero swallowed errors: no empty `catch` blocks, no `try?` in business logic
- Closures must use `[weak self]` or `[unowned self]` based on lifecycle

**Architecture**
- Views only bind to ViewModels — no direct access to GRDB or SwiftTerm
- All external dependencies injected via `init`, not accessed as singletons
- New protocols require a matching `Mock<Name>` and contract test

**Testing**
- New Repository/Service code must include unit tests
- New protocols require: `Mock<Name>` + `ContractTests` entry
- Time-sensitive logic must inject the `Clock` protocol

## Commit Style

```
feat(terminal): add OSC 133 sequence parsing
fix(input): correct cursor position on click-to-navigate
perf(session): move GRDB reads off main thread
test(services): add contract tests for SessionRepository
docs: update build instructions
```

Format: `type(scope): description` — keep the first line under 72 characters.

## Submitting a Pull Request

1. Fork the repo and create a feature branch from `main`
2. Run `make ci-local` — all checks must pass
3. Open a PR with a clear description of what changed and why
4. Link any related issues

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
