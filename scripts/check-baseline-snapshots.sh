#!/usr/bin/env bash
# check-baseline-snapshots.sh
#
# Wave 0 baseline freeze: locks in three measurable invariants by
# comparing the current state against snapshot files committed to
# `scripts/baseline/`. Any drift fails the check and prints exactly
# which file changed; the developer must either revert the change or
# explicitly update the baseline (which becomes a reviewer-visible
# diff in the PR).
#
# Invariants:
#   1. `.swiftlint.yml` `excluded:` lines (line numbers + content) match
#      `scripts/baseline/swiftlint-excluded.txt`. Adding or removing an
#      exclusion → fail.
#   2. `.gitignore` reverse-glob unblocks of `Sources/Termura/Harness/`
#      stubs match `scripts/baseline/gitignore-stub-allowlist.txt`.
#      Adding a 6th unblock or dropping one → fail.
#   3. Private-impl type names mentioned in `Sources/Termura/Harness/*.swift`
#      match `scripts/baseline/harness-stub-symbols.txt`. Wave 1 will
#      reduce this set; Wave 2 will remove it entirely. Anything else
#      is a regression.
#
# Exit codes:
#   0 = baseline intact
#   1 = drift (one or more snapshot files mismatch)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE_DIR="$REPO_ROOT/scripts/baseline"

if [[ ! -d "$BASELINE_DIR" ]]; then
    echo "FAIL: baseline directory missing at $BASELINE_DIR" >&2
    echo "       Run 'bash scripts/update-baselines.sh' to initialise." >&2
    exit 1
fi

FAILED=0

compare() {
    local label="$1" current="$2" baseline="$3"
    if ! diff -u "$baseline" <(echo "$current") >/dev/null 2>&1; then
        echo "FAIL: $label drifted from baseline." >&2
        echo "      Baseline: $baseline" >&2
        echo "      Diff (- baseline / + current):" >&2
        diff -u "$baseline" <(echo "$current") | sed 's/^/        /' >&2 || true
        FAILED=1
    fi
}

# 1. SwiftLint excluded lines
CURRENT_LINT_EXCL="$(grep -nE '^\s*excluded:' "$REPO_ROOT/.swiftlint.yml" || true)"
compare "SwiftLint excluded lines" "$CURRENT_LINT_EXCL" "$BASELINE_DIR/swiftlint-excluded.txt"

# 2. .gitignore Harness reverse-glob unblocks
CURRENT_GITIGNORE_UNBLOCKS="$(grep -nE '^!Sources/Termura/Harness' "$REPO_ROOT/.gitignore" || true)"
compare ".gitignore Harness unblocks" "$CURRENT_GITIGNORE_UNBLOCKS" "$BASELINE_DIR/gitignore-stub-allowlist.txt"

# 3. Private type names referenced in Harness/ stubs
PATTERN='RemoteIntegrationFactory|RemoteServerHarness|RemoteEnvelopeRouter|RemoteAgentBridgeAssembly|RemoteAgentXPCClient|AppMailboxXPCBridge|AgentInjectedCloudKitIngress|TrustedSourceGate|RemoteAgentAutoConnector|AgentVirtualReplyChannel'
if [[ -d "$REPO_ROOT/Sources/Termura/Harness" ]]; then
    CURRENT_STUB_SYMBOLS="$(grep -hoE "$PATTERN" "$REPO_ROOT"/Sources/Termura/Harness/*.swift 2>/dev/null | sort -u || true)"
else
    # Wave 2 deletes the directory; baseline file should then also be empty.
    CURRENT_STUB_SYMBOLS=""
fi
compare "Harness/ stub private-symbol references" "$CURRENT_STUB_SYMBOLS" "$BASELINE_DIR/harness-stub-symbols.txt"

if [[ $FAILED -ne 0 ]]; then
    echo "" >&2
    echo "Resolve drift in one of two ways:" >&2
    echo "  1. Revert the change that caused drift." >&2
    echo "  2. If the change is intentional (e.g. a Wave 2 stub removal), update" >&2
    echo "     the matching file in scripts/baseline/ and re-run this check." >&2
    echo "     The baseline diff appears in the PR for reviewer scrutiny." >&2
    exit 1
fi

echo "OK: open-core baseline snapshots match (.swiftlint.yml excluded, .gitignore Harness unblocks, Harness/ stub symbols)."
exit 0
