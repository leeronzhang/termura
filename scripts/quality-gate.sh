#!/usr/bin/env bash

set -euo pipefail

MODE="repo"
STRICT_TOOLS=0
INCLUDE_PRIVATE=0

for arg in "$@"; do
    case "$arg" in
        --staged)
            MODE="staged"
            ;;
        --ci)
            STRICT_TOOLS=1
            ;;
        --include-private)
            INCLUDE_PRIVATE=1
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--staged] [--ci] [--include-private]" >&2
            exit 2
            ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# When the private termura-harness sibling exists alongside this repo and the
# caller explicitly asked for it (or invoked us via the harness wrapper), we
# scan both repos under the same gate. Private path resolution is relative to
# the public repo's cwd so a single config tree drives both. Public-only checks
# (xcstrings catalog, project.yml ↔ pbxproj sync, layer deps tied to Termura
# Session/Output/Input) are not duplicated for private — those concepts don't
# exist there.
HARNESS_ROOT=""
if [[ $INCLUDE_PRIVATE -eq 1 ]]; then
    if [[ ! -d "$REPO_ROOT/../termura-harness" ]]; then
        echo "FAIL: --include-private requested but ../termura-harness sibling missing" >&2
        exit 1
    fi
    HARNESS_ROOT="$(cd "$REPO_ROOT/../termura-harness" && pwd)"
fi

# Source roots passed to multi-root helpers. Public roots first so violation
# output stays grouped sensibly when the same helper runs across both repos.
PUBLIC_TERMURA_ROOT="Sources/Termura"
PUBLIC_PACKAGE_ROOTS=()
if [[ -d Packages ]]; then
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        PUBLIC_PACKAGE_ROOTS+=("$pkg")
    done < <(find Packages -mindepth 2 -maxdepth 2 -type d -name "Sources" 2>/dev/null | sort)
fi

PRIVATE_TERMURA_LIKE_ROOTS=()
PRIVATE_VIEW_ROOTS=()
PRIVATE_BARE_DATE_ROOTS=()
PRIVATE_SOURCE_ROOTS=()
if [[ -n "$HARNESS_ROOT" ]]; then
    if [[ -d "$HARNESS_ROOT/Sources" ]]; then
        PRIVATE_SOURCE_ROOTS+=("$HARNESS_ROOT/Sources")
        PRIVATE_TERMURA_LIKE_ROOTS+=("$HARNESS_ROOT/Sources")
        PRIVATE_BARE_DATE_ROOTS+=("$HARNESS_ROOT/Sources")
    fi
    if [[ -d "$HARNESS_ROOT/iOS/TermuraRemote" ]]; then
        PRIVATE_SOURCE_ROOTS+=("$HARNESS_ROOT/iOS/TermuraRemote")
        PRIVATE_TERMURA_LIKE_ROOTS+=("$HARNESS_ROOT/iOS/TermuraRemote")
        PRIVATE_BARE_DATE_ROOTS+=("$HARNESS_ROOT/iOS/TermuraRemote")
        if [[ -d "$HARNESS_ROOT/iOS/TermuraRemote/Features" ]]; then
            PRIVATE_VIEW_ROOTS+=("$HARNESS_ROOT/iOS/TermuraRemote/Features")
        fi
    fi
    if [[ -d "$HARNESS_ROOT/LaunchAgent/Sources" ]]; then
        PRIVATE_SOURCE_ROOTS+=("$HARNESS_ROOT/LaunchAgent/Sources")
        PRIVATE_TERMURA_LIKE_ROOTS+=("$HARNESS_ROOT/LaunchAgent/Sources")
        PRIVATE_BARE_DATE_ROOTS+=("$HARNESS_ROOT/LaunchAgent/Sources")
    fi
fi

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo "Termura Quality Gate"
if [[ -n "$HARNESS_ROOT" ]]; then
    echo "  scope: public + private (termura-harness)"
else
    echo "  scope: public only"
fi
echo "======================================"

have_tool() {
    command -v "$1" >/dev/null 2>&1
}

record_failure() {
    ERRORS=$((ERRORS + 1))
}

record_warning() {
    WARNINGS=$((WARNINGS + 1))
}

run_gate_check() {
    local label="$1"
    shift

    echo "-> ${label}..."
    set +e
    "$@"
    local status=$?
    set -e

    case "$status" in
        0)
            return 0
            ;;
        3)
            # Advisory exit (file-size soft cap, view-global-access, …).
            # Default policy: STRICT BASELINE — treat advisories as
            # failures so the current 0-violation state is locked in.
            # Any PR that introduces a new advisory hit fails the gate.
            # Local incremental work that wants the legacy WARN behaviour
            # can opt out with `ALLOW_ADVISORY_WARN=1`.
            if [[ "${ALLOW_ADVISORY_WARN:-0}" == "1" ]]; then
                record_warning
            else
                record_failure
            fi
            return 0
            ;;
        *)
            record_failure
            return 0
            ;;
    esac
}

run_required_tool() {
    local tool="$1"
    local install_hint="$2"

    if have_tool "$tool"; then
        return 0
    fi

    if [[ $STRICT_TOOLS -eq 1 ]]; then
        echo -e "${RED}FAIL: required tool missing: ${tool}${NC}"
        echo "  Install hint: ${install_hint}"
        record_failure
    else
        echo -e "${YELLOW}WARN: ${tool} not installed, skipping (${install_hint})${NC}"
        record_warning
    fi

    return 1
}

# Resolve which Swift files this run targets. Layout matches the multi-root
# scope: when private is included we add the harness sources to the staged /
# repo file list so SwiftLint and SwiftFormat see both halves.
collect_swift_files_for_root() {
    local root="$1"
    local root_pattern_relative="${root#"$REPO_ROOT/"}"
    if [[ "$MODE" == "staged" ]]; then
        # Staged-file paths from `git diff --cached` are relative to whichever
        # repo holds the staged commit. From the public repo we ask for files
        # under the absolute root; from private repos the harness wrapper
        # invokes us with a separate gate so this branch only ever hits public
        # staged paths anyway.
        if [[ "$root" == "$REPO_ROOT/$PUBLIC_TERMURA_ROOT" || "$root" == "$REPO_ROOT/Sources" ]]; then
            git diff --cached --name-only --diff-filter=ACMR \
                | grep -E '^Sources/.*\.swift$' || true
            return
        fi
        if [[ "$root" == "$REPO_ROOT/Packages"* ]]; then
            git diff --cached --name-only --diff-filter=ACMR \
                | grep -E "^${root_pattern_relative}/.*\.swift$" || true
            return
        fi
        # Private roots in staged mode: scan all swift files under the root,
        # since the hook is triggered by the private repo's own staged set.
        find "$root" -name "*.swift" -type f
    else
        find "$root" -name "*.swift" -type f
    fi
}

ci_changed_swift_files() {
    local base_ref=""

    if [[ -n "${GITHUB_BASE_REF:-}" ]] && git show-ref --verify --quiet "refs/remotes/origin/${GITHUB_BASE_REF}"; then
        base_ref="origin/${GITHUB_BASE_REF}"
    elif [[ -n "${GITHUB_ACTIONS:-}" ]] && git rev-parse --verify HEAD^ >/dev/null 2>&1; then
        base_ref="HEAD^"
    fi

    if [[ -n "$base_ref" ]]; then
        git diff --name-only --diff-filter=ACMR "${base_ref}...HEAD" \
            | grep -E '^Sources/.*\.swift$' || true
    else
        {
            git diff --name-only --diff-filter=ACMR HEAD -- Sources 2>/dev/null
            git ls-files --others --exclude-standard Sources 2>/dev/null
        } | grep -E '^Sources/.*\.swift$' | sort -u || true
    fi
}

SWIFT_FILES=()
PUBLIC_SOURCE_ROOTS_ABS=("$REPO_ROOT/Sources")
if [[ ${#PUBLIC_PACKAGE_ROOTS[@]} -gt 0 ]]; then
    for pkg in "${PUBLIC_PACKAGE_ROOTS[@]}"; do
        PUBLIC_SOURCE_ROOTS_ABS+=("$REPO_ROOT/$pkg")
    done
fi

if [[ "$MODE" == "staged" ]]; then
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        SWIFT_FILES+=("$f")
    done < <(git diff --cached --name-only --diff-filter=ACMR | grep -E '\.swift$' || true)
elif [[ $STRICT_TOOLS -eq 1 ]]; then
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        SWIFT_FILES+=("$f")
    done < <(ci_changed_swift_files)
else
    for root in "${PUBLIC_SOURCE_ROOTS_ABS[@]}"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            SWIFT_FILES+=("$f")
        done < <(find "$root" -name "*.swift" -type f | sort)
    done
fi

# Add private files to the lint set when --include-private is on. In staged
# mode the public hook only sees public staged paths so we leave private out;
# the private repo's own hook drives that pass via its wrapper.
if [[ -n "$HARNESS_ROOT" && "$MODE" != "staged" ]]; then
    for root in "${PRIVATE_SOURCE_ROOTS[@]}"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            SWIFT_FILES+=("$f")
        done < <(find "$root" -name "*.swift" -type f | sort)
    done
fi

staged_or_repo_source_files() {
    if [[ "$MODE" == "staged" ]]; then
        git diff --cached --name-only --diff-filter=ACMR \
            | grep -E '\.(swift|sh|m|h)$' || true
    else
        find Sources scripts -type f \( -name "*.swift" -o -name "*.sh" -o -name "*.m" -o -name "*.h" \) | sort
        if [[ -n "$HARNESS_ROOT" ]]; then
            for root in "${PRIVATE_SOURCE_ROOTS[@]}"; do
                [[ -d "$root" ]] || continue
                find "$root" -type f \( -name "*.swift" -o -name "*.m" -o -name "*.h" \) | sort
            done
        fi
    fi
}

echo "-> SwiftLint strict check..."
if run_required_tool "swiftlint" "brew install swiftlint"; then
    SWIFTLINT_CACHE_PATH="${TMPDIR:-/tmp}/termura-swiftlint.cache"
    if [[ ${#SWIFT_FILES[@]} -eq 0 ]]; then
        echo -e "${GREEN}OK: No Swift source changes to lint${NC}"
    elif ! swiftlint lint --strict --quiet --cache-path "$SWIFTLINT_CACHE_PATH" \
        --config "$REPO_ROOT/.swiftlint.yml" "${SWIFT_FILES[@]}"; then
        echo -e "${RED}FAIL: SwiftLint errors detected.${NC}"
        record_failure
    else
        echo -e "${GREEN}OK: SwiftLint passed${NC}"
    fi
fi

echo "-> SwiftFormat check..."
if run_required_tool "swiftformat" "brew install swiftformat"; then
    if [[ ${#SWIFT_FILES[@]} -eq 0 ]]; then
        echo -e "${GREEN}OK: No Swift source changes to format-check${NC}"
    elif ! swiftformat --lint --quiet --config "$REPO_ROOT/.swiftformat" "${SWIFT_FILES[@]}"; then
        echo -e "${RED}FAIL: SwiftFormat violations detected.${NC}"
        record_failure
    else
        echo -e "${GREEN}OK: SwiftFormat passed${NC}"
    fi
fi

echo "Fast Gate"
echo "--------------------------------------"
run_gate_check "Suppression check" bash scripts/check-suppressions.sh "$REPO_ROOT/Sources/Termura"
if [[ -n "$HARNESS_ROOT" ]]; then
    for root in "${PRIVATE_TERMURA_LIKE_ROOTS[@]}"; do
        run_gate_check "Suppression check (${root#"$HARNESS_ROOT/"})" \
            bash scripts/check-suppressions.sh "$root"
    done
fi

run_gate_check "Redundant import check (Sources/Termura)" \
    bash scripts/check-redundant-imports.sh Sources/Termura
if [[ -n "$HARNESS_ROOT" ]]; then
    for root in "${PRIVATE_TERMURA_LIKE_ROOTS[@]}"; do
        run_gate_check "Redundant import check (${root#"$HARNESS_ROOT/"})" \
            bash scripts/check-redundant-imports.sh "$root"
    done
fi

run_gate_check "Hardcoded AppKit string check" bash scripts/check-hardcoded-strings.sh Sources/Termura
# AppKit strings only appear in macOS surfaces; private-repo equivalents on
# the Mac side live under Sources/ and follow the same rule. iOS UI uses
# SwiftUI primitives that don't trigger this scanner so the same regex is safe.
if [[ -n "$HARNESS_ROOT" && -d "$HARNESS_ROOT/Sources" ]]; then
    run_gate_check "Hardcoded AppKit string check (harness Sources)" \
        bash scripts/check-hardcoded-strings.sh "$HARNESS_ROOT/Sources"
fi

run_gate_check "xcstrings coverage check" bash scripts/check-xcstrings-coverage.sh

run_gate_check "TextEditor accessibility check" \
    bash scripts/check-texteditor-accessibility.sh Sources/Termura/Views

run_gate_check "Bare Date() check" bash scripts/check-bare-date.sh
if [[ -n "$HARNESS_ROOT" ]]; then
    for root in "${PRIVATE_BARE_DATE_ROOTS[@]}"; do
        run_gate_check "Bare Date() check (${root#"$HARNESS_ROOT/"})" \
            bash scripts/check-bare-date.sh "$root"
    done
fi

run_gate_check "Layer dependency check" bash scripts/check-layer-deps.sh
run_gate_check "Version sync check" bash scripts/check-version-sync.sh
run_gate_check "Open-core baseline drift check" bash scripts/check-baseline-drift.sh
run_gate_check "Open-core baseline snapshots check" bash scripts/check-baseline-snapshots.sh

echo "-> Forbidden Swift pattern checks..."
# Pre-build the list of paths the inline Python should scan. We pass them via
# argv so the heredoc stays self-contained; the script falls back to the
# legacy single-root behaviour when nothing is passed.
FORBIDDEN_ROOTS=()
if [[ "$MODE" != "staged" ]]; then
    FORBIDDEN_ROOTS+=("$REPO_ROOT/Sources")
    if [[ -n "$HARNESS_ROOT" && ${#PRIVATE_SOURCE_ROOTS[@]} -gt 0 ]]; then
        for root in "${PRIVATE_SOURCE_ROOTS[@]}"; do
            FORBIDDEN_ROOTS+=("$root")
        done
    fi
fi
FORBIDDEN_ARGS=("$MODE")
if [[ ${#FORBIDDEN_ROOTS[@]} -gt 0 ]]; then
    FORBIDDEN_ARGS+=("${FORBIDDEN_ROOTS[@]}")
fi
if ! FORBIDDEN_OUTPUT="$(python3 - "${FORBIDDEN_ARGS[@]}" <<'PYEOF'
import pathlib
import re
import subprocess
import sys

mode = sys.argv[1]
roots = [pathlib.Path(p) for p in sys.argv[2:]]
cwd = pathlib.Path.cwd()

# `\btry\?` matches `try?` regardless of the next character. The previous
# regex `\btry\?\b` required a word boundary after `?`, which fails for the
# common `try? expr` form (space is non-word, so no boundary). Bug fixed.
checks = [
    ("force unwrap / try! / as!", [
        re.compile(r"\btry!"),
        re.compile(r"\bas!"),
        re.compile(r"=\s*!\s*$"),
    ]),
    ("fatalError in production code", [re.compile(r"\bfatalError\s*\(")]),
    ("try? error swallowing", [re.compile(r"\btry\?")]),
    ("legacy DispatchQueue API", [
        re.compile(r"DispatchQueue\.main\.async\b"),
        re.compile(r"DispatchQueue\.main\.asyncAfter\b"),
        re.compile(r"DispatchQueue\.global\s*\("),
    ]),
]

def list_files() -> list[pathlib.Path]:
    if mode == "staged":
        proc = subprocess.run(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
            capture_output=True,
            text=True,
            check=True,
        )
        files = []
        for rel in proc.stdout.splitlines():
            if rel.startswith("Sources/") and rel.endswith(".swift"):
                path = cwd / rel
                if path.exists():
                    files.append(path)
        return files
    if not roots:
        return sorted((cwd / "Sources").rglob("*.swift"))
    files: list[pathlib.Path] = []
    for root in roots:
        if not root.exists():
            continue
        files.extend(sorted(root.rglob("*.swift")))
    return files

violations: list[str] = []

for path in list_files():
    try:
        rel = path.relative_to(cwd)
    except ValueError:
        rel = path
    with path.open(encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, start=1):
            stripped = line.strip()
            if stripped.startswith("//") or "swiftlint:disable" in line:
                continue
            for description, patterns in checks:
                if any(pattern.search(line) for pattern in patterns):
                    violations.append(f"{description}|{rel}:{lineno}: {line.rstrip()}")

if violations:
    grouped: dict[str, list[str]] = {}
    for entry in violations:
        key, detail = entry.split("|", 1)
        grouped.setdefault(key, []).append(detail)
    for key, details in grouped.items():
        print(f"FAIL: {key}")
        for detail in details:
            print(f"  {detail}")
    sys.exit(1)

print("OK: No forbidden Swift patterns found")
PYEOF
)"
then
    echo "$FORBIDDEN_OUTPUT"
    record_failure
else
    echo "$FORBIDDEN_OUTPUT"
fi

echo ""
echo "Design Gate"
echo "--------------------------------------"
if [[ "$MODE" == "staged" ]]; then
    run_gate_check "Legacy Mock placement audit" bash scripts/mock-guard-audit.sh --staged Sources/Termura
    run_gate_check "File-size budget check" bash scripts/check-file-size.sh --staged Sources/Termura
    run_gate_check "View/ViewModel global access advisory" bash scripts/check-view-global-access.sh --staged
    run_gate_check "Background task ownership advisory" bash scripts/check-task-ownership.sh --staged Sources/Termura
else
    run_gate_check "Legacy Mock placement audit (Sources/Termura)" \
        bash scripts/mock-guard-audit.sh Sources/Termura
    if [[ -n "$HARNESS_ROOT" ]]; then
        for root in "${PRIVATE_TERMURA_LIKE_ROOTS[@]}"; do
            run_gate_check "Legacy Mock placement audit (${root#"$HARNESS_ROOT/"})" \
                bash scripts/mock-guard-audit.sh "$root"
        done
    fi
    run_gate_check "File-size budget check (Sources/Termura)" \
        bash scripts/check-file-size.sh Sources/Termura
    if [[ -n "$HARNESS_ROOT" ]]; then
        for root in "${PRIVATE_TERMURA_LIKE_ROOTS[@]}"; do
            run_gate_check "File-size budget check (${root#"$HARNESS_ROOT/"})" \
                bash scripts/check-file-size.sh "$root"
        done
    fi
    run_gate_check "View/ViewModel global access advisory" \
        bash scripts/check-view-global-access.sh
    if [[ -n "$HARNESS_ROOT" ]]; then
        for root in "${PRIVATE_VIEW_ROOTS[@]}"; do
            run_gate_check "View/ViewModel global access advisory (${root#"$HARNESS_ROOT/"})" \
                bash scripts/check-view-global-access.sh "$root"
        done
    fi
    run_gate_check "Background task ownership advisory (Sources/Termura)" \
        bash scripts/check-task-ownership.sh Sources/Termura
    if [[ -n "$HARNESS_ROOT" ]]; then
        for root in "${PRIVATE_TERMURA_LIKE_ROOTS[@]}"; do
            run_gate_check "Background task ownership advisory (${root#"$HARNESS_ROOT/"})" \
                bash scripts/check-task-ownership.sh "$root"
        done
    fi
fi

run_gate_check "Entitlements hygiene gate" \
    env HARNESS_ROOT="$HARNESS_ROOT" bash scripts/check-entitlements-hygiene.sh

if [[ -n "$HARNESS_ROOT" ]]; then
    run_gate_check "iOS App Store permissions / privacy gate" \
        env IOS_HARNESS_ROOT="$HARNESS_ROOT" bash scripts/check-ios-permissions.sh
fi

echo "-> Harness private file leak check..."
HARNESS_WHITELIST='HarnessModels.swift|RuleFileRepositoryProtocol.swift|HarnessViewModel\+Stub.swift|ExperienceCodifier\+Stub.swift|RemoteIntegration\+Stub.swift'
if [[ "$MODE" == "staged" ]]; then
    HARNESS_CANDIDATES="$(git diff --cached --name-only --diff-filter=ACMR | grep '^Sources/Termura/Harness/' || true)"
else
    HARNESS_CANDIDATES="$(find Sources/Termura/Harness -type f 2>/dev/null | sed 's#^\./##' || true)"
fi
HARNESS_LEAKED="$(printf '%s\n' "$HARNESS_CANDIDATES" | grep -vE "$HARNESS_WHITELIST" | sed '/^$/d' || true)"
if [[ -n "$HARNESS_LEAKED" ]]; then
    echo -e "${RED}FAIL: Private Harness file(s) detected:${NC}"
    echo "$HARNESS_LEAKED" | sed 's/^/  /'
    record_failure
else
    echo -e "${GREEN}OK: Harness directory is within whitelist${NC}"
fi

echo "-> Chinese character check..."
CHINESE_FILES="$(staged_or_repo_source_files | xargs -I{} grep -lP '[\x{4e00}-\x{9fff}\x{3400}-\x{4dbf}\x{20000}-\x{2a6df}\x{2a700}-\x{2b73f}\x{2b740}-\x{2b81f}\x{2b820}-\x{2ceaf}\x{f900}-\x{faff}\x{2f800}-\x{2fa1f}]' {} 2>/dev/null || true)"
if [[ -n "$CHINESE_FILES" ]]; then
    echo -e "${RED}FAIL: Chinese characters found in source-controlled code files:${NC}"
    echo "$CHINESE_FILES" | sed 's/^/  /'
    record_failure
else
    echo -e "${GREEN}OK: No Chinese characters in checked code files${NC}"
fi

echo ""
echo "======================================"
if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}FAIL: Quality gate failed with ${ERRORS} error(s), ${WARNINGS} warning(s).${NC}"
    exit 1
fi

if [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}WARN: Quality gate passed with ${WARNINGS} warning(s).${NC}"
else
    echo -e "${GREEN}OK: All quality checks passed${NC}"
fi
