#!/usr/bin/env bash

set -euo pipefail

MODE="repo"
STRICT_TOOLS=0

for arg in "$@"; do
    case "$arg" in
        --staged)
            MODE="staged"
            ;;
        --ci)
            STRICT_TOOLS=1
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--staged] [--ci]" >&2
            exit 2
            ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo "Termura Quality Gate"
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

staged_or_repo_swift_files() {
    if [[ "$MODE" == "staged" ]]; then
        git diff --cached --name-only --diff-filter=ACMR \
            | grep -E '^Sources/.*\.swift$' || true
    else
        find Sources -name "*.swift" -type f | sort
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

collect_swift_files() {
    if [[ "$MODE" == "staged" ]]; then
        staged_or_repo_swift_files
    elif [[ $STRICT_TOOLS -eq 1 ]]; then
        ci_changed_swift_files
    else
        staged_or_repo_swift_files
    fi
}

SWIFT_FILES=()
while IFS= read -r swift_file; do
    [[ -n "$swift_file" ]] || continue
    SWIFT_FILES+=("$swift_file")
done < <(collect_swift_files)

staged_or_repo_source_files() {
    if [[ "$MODE" == "staged" ]]; then
        git diff --cached --name-only --diff-filter=ACMR \
            | grep -E '\.(swift|sh|m|h)$' || true
    else
        find Sources scripts -type f \( -name "*.swift" -o -name "*.sh" -o -name "*.m" -o -name "*.h" \) | sort
    fi
}

echo "-> SwiftLint strict check..."
if run_required_tool "swiftlint" "brew install swiftlint"; then
    SWIFTLINT_CACHE_PATH="${TMPDIR:-/tmp}/termura-swiftlint.cache"
    if [[ ${#SWIFT_FILES[@]} -eq 0 ]]; then
        echo -e "${GREEN}OK: No Swift source changes to lint${NC}"
    elif ! swiftlint lint --strict --quiet --cache-path "$SWIFTLINT_CACHE_PATH" "${SWIFT_FILES[@]}"; then
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
    elif ! swiftformat --lint --quiet "${SWIFT_FILES[@]}"; then
        echo -e "${RED}FAIL: SwiftFormat violations detected.${NC}"
        record_failure
    else
        echo -e "${GREEN}OK: SwiftFormat passed${NC}"
    fi
fi

echo "-> Redundant import check..."
if ! bash scripts/check-redundant-imports.sh Sources/Termura; then
    record_failure
fi

echo "-> Hardcoded AppKit string check..."
if ! bash scripts/check-hardcoded-strings.sh Sources/Termura; then
    record_failure
fi

echo "-> xcstrings coverage check..."
if ! bash scripts/check-xcstrings-coverage.sh; then
    record_failure
fi

echo "-> TextEditor accessibility check..."
if ! bash scripts/check-texteditor-accessibility.sh Sources/Termura/Views; then
    record_failure
fi

echo "-> Bare Date() check..."
if ! bash scripts/check-bare-date.sh; then
    record_failure
fi

echo "-> Layer dependency check..."
if ! bash scripts/check-layer-deps.sh; then
    record_failure
fi

echo "-> Mock #if DEBUG guard audit..."
if ! bash scripts/mock-guard-audit.sh; then
    record_failure
fi

echo "-> Forbidden Swift pattern checks..."
if ! FORBIDDEN_OUTPUT="$(python3 - "$MODE" <<'PYEOF'
import pathlib
import re
import subprocess
import sys

mode = sys.argv[1]
root = pathlib.Path.cwd()

checks = [
    ("force unwrap / try! / as!", [
        re.compile(r"\btry!"),
        re.compile(r"\bas!"),
        re.compile(r"=\s*!\s*$"),
    ]),
    ("fatalError in production code", [re.compile(r"\bfatalError\s*\(")]),
    ("try? error swallowing", [re.compile(r"\btry\?\b")]),
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
                path = root / rel
                if path.exists():
                    files.append(path)
        return files
    return sorted((root / "Sources").rglob("*.swift"))

violations: list[str] = []

for path in list_files():
    rel = path.relative_to(root)
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

echo "-> Harness private file leak check..."
HARNESS_WHITELIST='HarnessModels.swift|RuleFileRepositoryProtocol.swift|HarnessViewModel\+Stub.swift|ExperienceCodifier\+Stub.swift'
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
