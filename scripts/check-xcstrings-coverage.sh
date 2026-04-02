#!/usr/bin/env bash
# check-xcstrings-coverage.sh
#
# Verifies that every key used in String(localized: "KEY") calls in
# Sources/Termura has a corresponding entry in Resources/Localizable.xcstrings.
#
# Rationale: a missing entry causes silent fallback to the key at runtime.
# English display is unaffected, but future translations will silently drop
# the string. Catching this at commit time prevents catalog drift.
#
# Usage:
#   ./scripts/check-xcstrings-coverage.sh

set -euo pipefail

SOURCES="Sources/Termura"
CATALOG="Resources/Localizable.xcstrings"
FAIL=0

if [ ! -f "${CATALOG}" ]; then
    echo "ERROR: ${CATALOG} not found."
    exit 1
fi

echo "=== xcstrings coverage check ==="

# Extract all keys present in the catalog (lines of the form `"KEY" :`)
catalog_keys=$(python3 - <<'EOF'
import json, sys
with open("Resources/Localizable.xcstrings") as f:
    data = json.load(f)
for key in data.get("strings", {}).keys():
    print(key)
EOF
)

# Extract all String(localized: "KEY") literal keys from Swift source.
# Matches: String(localized: "...") — single-line, static string keys only.
# Dynamic keys (String interpolation inside localized:) are intentionally skipped.
used_keys=$(grep -rh --include="*.swift" -E 'String\(localized:\s*"[^"\\]*"' "${SOURCES}" \
    | grep -oE 'String\(localized:\s*"[^"\\]+"' \
    | grep -oE '"[^"\\]+"' \
    | tr -d '"' \
    | sort -u)

missing=()
while IFS= read -r key; do
    if ! echo "${catalog_keys}" | grep -qxF "${key}"; then
        missing+=("${key}")
    fi
done <<< "${used_keys}"

if [ ${#missing[@]} -eq 0 ]; then
    echo "  OK: all String(localized:) keys are present in ${CATALOG}."
    echo "=== Coverage check passed ==="
    exit 0
fi

echo ""
echo "FAIL: the following String(localized:) keys are missing from ${CATALOG}:"
for key in "${missing[@]}"; do
    # Show which file(s) use this key
    files=$(grep -rl --include="*.swift" "String(localized: \"${key}\"" "${SOURCES}" | tr '\n' ' ')
    echo "  \"${key}\"  (used in: ${files})"
done
echo ""
echo "Add the missing keys to ${CATALOG} before committing."
echo "=== Coverage check FAILED ==="
FAIL=1
exit ${FAIL}
