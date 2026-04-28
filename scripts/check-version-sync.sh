#!/usr/bin/env bash
# Verifies that MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml
# match the values in Termura.xcodeproj/project.pbxproj. Divergence usually
# means the user edited Xcode UI without running sync-version-from-xcode.sh,
# which would silently lose the edit on the next `xcodegen generate`.
#
# Exit codes:
#   0  in sync, or pbxproj absent (skipped — CI without an Xcode generation)
#   1  divergent (with remediation hint)
#   3  warning (skip with warn) — kept available; not used today

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PBXPROJ="Termura.xcodeproj/project.pbxproj"
PROJECT_YML="project.yml"

if [[ ! -f "$PBXPROJ" ]]; then
    echo "OK: $PBXPROJ not present — skipping version-sync check (run \`xcodegen generate\` first)."
    exit 0
fi

extract_unique() {
    local key="$1"
    grep -oE "${key} = [^;]+;" "$PBXPROJ" \
        | sed -E "s/${key} = (.+);/\\1/" \
        | sed -E 's/^"(.*)"$/\1/' \
        | sort -u
}

PBX_MV="$(extract_unique MARKETING_VERSION)"
PBX_PV="$(extract_unique CURRENT_PROJECT_VERSION)"

YML_MV="$(grep -E '^[[:space:]]+MARKETING_VERSION:' "$PROJECT_YML" | head -1 | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/' || true)"
YML_PV="$(grep -E '^[[:space:]]+CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | head -1 | sed -E 's/.*CURRENT_PROJECT_VERSION:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/' || true)"

FAIL=0

if [[ -z "$PBX_MV" || -z "$PBX_PV" ]]; then
    echo "FAIL: pbxproj is missing MARKETING_VERSION or CURRENT_PROJECT_VERSION."
    echo "  Open Xcode -> Termura target -> General -> Identity and set Version + Build."
    exit 1
fi

if [[ "$(echo "$PBX_MV" | wc -l | tr -d ' ')" -ne 1 ]]; then
    echo "FAIL: pbxproj has multiple distinct MARKETING_VERSION values:"
    echo "$PBX_MV" | sed 's/^/  /'
    echo "  Make Debug/Release/Free configurations agree."
    FAIL=1
fi

if [[ "$(echo "$PBX_PV" | wc -l | tr -d ' ')" -ne 1 ]]; then
    echo "FAIL: pbxproj has multiple distinct CURRENT_PROJECT_VERSION values:"
    echo "$PBX_PV" | sed 's/^/  /'
    FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
    exit 1
fi

if [[ "$PBX_MV" != "$YML_MV" || "$PBX_PV" != "$YML_PV" ]]; then
    echo "FAIL: project.yml is out of sync with Xcode UI version edits."
    echo "  pbxproj:      MARKETING_VERSION=${PBX_MV}  CURRENT_PROJECT_VERSION=${PBX_PV}"
    echo "  project.yml:  MARKETING_VERSION=${YML_MV}  CURRENT_PROJECT_VERSION=${YML_PV}"
    echo "  Fix:          bash scripts/sync-version-from-xcode.sh"
    exit 1
fi

echo "OK: project.yml mirrors pbxproj (MARKETING_VERSION=${PBX_MV}, CURRENT_PROJECT_VERSION=${PBX_PV})."
exit 0
