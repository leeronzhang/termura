#!/usr/bin/env bash
# Cross-target entitlements hygiene gate. Walks every checked-in
# .entitlements file in the public + private repos and bans configuration
# patterns that ship the wrong value to production users.
#
# Why this is its own gate: the iOS App Store gate (check-ios-permissions.sh)
# is iOS-only because App Store rules don't apply to Mac DMG distribution.
# But "shipping the wrong aps-environment value to production" is a universal
# trap on any platform that uses APNs / CloudKit silent push, so this gate
# runs across both platforms.
#
# Currently enforces:
#   1. com.apple.developer.aps-environment, IF declared, must be the literal
#      "development" — Apple's archive flow re-signs distribution builds
#      with the production value pulled from the provisioning profile, so
#      hardcoding "production" in the source file produces the wrong result
#      for Debug runs and is a sign someone tried to "fix it forward". Apps
#      that need silent push MUST declare the key (Push Notifications
#      capability requires it); this gate's prior incarnation banned the
#      key outright, which mis-led an audit fix into deleting it and
#      breaking silent push entirely. Do not re-introduce that ban.
#
# Skips files inside vendor/, .build/, .derived/, DerivedData/.
#
# Exit codes: 0 = pass, 1 = fail.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLIC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# HARNESS_ROOT is supplied explicitly by the caller (quality-gate.sh sets it
# from its own --include-private resolution). No literal sibling-path fallback
# here: hardcoding the private repo's relative path would trip the open-core
# leak scan (CLAUDE.md §12.3, LEAK_PATTERN is path-only). When the caller
# omits the env var we run public-only and skip private entitlements.
HARNESS_ROOT="${HARNESS_ROOT:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

SCAN_ROOTS=("$PUBLIC_ROOT")
if [[ -d "$HARNESS_ROOT" ]]; then
    SCAN_ROOTS+=("$HARNESS_ROOT")
fi

# Returns the value of `aps-environment` in the entitlements file, or empty
# string if the key is absent. Uses plutil so plist format (XML / binary)
# does not matter.
extract_aps_environment() {
    local path="$1"
    /usr/bin/plutil -extract 'aps-environment' raw -o - "$path" 2>/dev/null || true
}

FOUND_ANY=0
for root in "${SCAN_ROOTS[@]}"; do
    while IFS= read -r ent; do
        [[ -n "$ent" ]] || continue
        FOUND_ANY=1
        value="$(extract_aps_environment "$ent")"
        if [[ -z "$value" ]]; then
            continue
        fi
        if [[ "$value" != "development" ]]; then
            echo -e "${RED}FAIL${NC}: aps-environment in $ent is \"$value\""
            echo "       Must be the literal \"development\". Xcode's archive flow"
            echo "       re-signs distribution builds with the production value"
            echo "       from the provisioning profile, so hardcoding \"production\""
            echo "       breaks Debug runs and yields no benefit for Release."
            ERRORS=$((ERRORS + 1))
        fi
    done < <(find "$root" -type f -name '*.entitlements' \
                 -not -path '*/vendor/*' \
                 -not -path '*/.build/*' \
                 -not -path '*/.derived/*' \
                 -not -path '*/DerivedData/*' \
                 -not -path '*/build/*' 2>/dev/null | sort)
done

if [[ $FOUND_ANY -eq 0 ]]; then
    echo -e "${YELLOW}WARN${NC}: no .entitlements files found under: ${SCAN_ROOTS[*]}"
    exit 0
fi

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}FAIL: entitlements hygiene gate failed with $ERRORS error(s).${NC}"
    exit 1
fi

echo -e "${GREEN}OK: entitlements hygiene gate passed.${NC}"
exit 0
