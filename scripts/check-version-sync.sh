#!/usr/bin/env bash
# Verifies that every Xcode project's MARKETING_VERSION /
# CURRENT_PROJECT_VERSION agrees with the xcconfig that owns it.
#
# In the xcconfig-as-source-of-truth design, a freshly regenerated pbxproj
# contains NO MARKETING_VERSION / CURRENT_PROJECT_VERSION lines — both come
# from `Versions.xcconfig` via baseConfigurationReference. If a pbxproj
# does carry the keys, they are either:
#   1. Xcode UI overrides the user just typed and hasn't yet round-tripped
#      through `regen-all.sh` (which calls sync-version-from-xcode.sh and
#      then xcodegen, after which the override disappears), OR
#   2. a stale pbxproj from before the migration to xcconfig.
#
# Either way, the safe rule is: pbxproj override must equal xcconfig value.
# A divergence means a UI edit is pending and would be silently lost on the
# next xcodegen run — which is exactly the bug we set out to prevent.
#
# Sibling private repo path is supplied via the env var TERMURA_HARNESS_ROOT
# by the caller (quality-gate.sh / pre-commit). Keeping the string out of
# this script preserves the open-core leak baseline (CLAUDE.md §12.3).
#
# Exit codes:
#   0  in sync (or every pbxproj is absent — clean clone)
#   1  divergent (with remediation hint)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PUBLIC_XCCONFIG="$REPO_ROOT/Versions.xcconfig"
PUBLIC_MAC_PBX="$REPO_ROOT/Termura.xcodeproj/project.pbxproj"

SIBLING="${TERMURA_HARNESS_ROOT:-}"
PRIVATE_MAC_PBX=""
PRIVATE_IOS_PBX=""
IOS_XCCONFIG=""
if [ -n "$SIBLING" ] && [ -d "$SIBLING" ]; then
    PRIVATE_MAC_PBX="$SIBLING/Termura-Mac.xcodeproj/project.pbxproj"
    PRIVATE_IOS_PBX="$SIBLING/iOS/TermuraRemote.xcodeproj/project.pbxproj"
    IOS_XCCONFIG="$SIBLING/iOS/Versions.xcconfig"
fi

extract_unique() {
    local pbx="$1" key="$2"
    [ -f "$pbx" ] || return 0
    grep -oE "${key} = [^;]+;" "$pbx" 2>/dev/null \
        | sed -E "s/${key} = (.+);/\\1/" \
        | sed -E 's/^"(.*)"$/\1/' \
        | sort -u
}

read_xcconfig() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" \
        | head -1 \
        | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//" \
        | sed -E 's/[[:space:]]*$//'
}

check_one() {
    local label="$1" pbx="$2" xcconfig="$3"

    if [ ! -f "$pbx" ]; then
        echo "skip [${label}]: pbxproj not generated yet."
        return 0
    fi
    if [ ! -f "$xcconfig" ]; then
        echo "FAIL [${label}]: ${xcconfig} is missing — Versions.xcconfig must be tracked."
        return 1
    fi

    local pbx_mv pbx_pv xc_mv xc_pv
    pbx_mv="$(extract_unique "$pbx" MARKETING_VERSION)"
    pbx_pv="$(extract_unique "$pbx" CURRENT_PROJECT_VERSION)"
    xc_mv="$(read_xcconfig "$xcconfig" MARKETING_VERSION)"
    xc_pv="$(read_xcconfig "$xcconfig" CURRENT_PROJECT_VERSION)"

    if [ -z "$xc_mv" ] || [ -z "$xc_pv" ]; then
        echo "FAIL [${label}]: ${xcconfig##*/} is missing MARKETING_VERSION or CURRENT_PROJECT_VERSION."
        return 1
    fi

    # No pbxproj override → a clean post-regen state. Build will read xcconfig.
    if [ -z "$pbx_mv" ] && [ -z "$pbx_pv" ]; then
        echo "OK [${label}]: pbxproj clean of overrides; build reads xcconfig (MARKETING_VERSION=${xc_mv}, CURRENT_PROJECT_VERSION=${xc_pv})."
        return 0
    fi

    # Multiple distinct override values inside one pbxproj would silently
    # ship inconsistent bundles. Always a hard fail.
    if [ "$(printf '%s\n' "$pbx_mv" | grep -cv '^$')" -gt 1 ]; then
        echo "FAIL [${label}]: pbxproj has multiple distinct MARKETING_VERSION values:"
        printf '  %s\n' "$pbx_mv"
        return 1
    fi
    if [ "$(printf '%s\n' "$pbx_pv" | grep -cv '^$')" -gt 1 ]; then
        echo "FAIL [${label}]: pbxproj has multiple distinct CURRENT_PROJECT_VERSION values:"
        printf '  %s\n' "$pbx_pv"
        return 1
    fi

    if [ "$pbx_mv" != "$xc_mv" ] || [ "$pbx_pv" != "$xc_pv" ]; then
        echo "FAIL [${label}]: pbxproj override differs from xcconfig — Xcode UI edit pending sync."
        echo "  pbxproj:   MARKETING_VERSION=${pbx_mv:-<unset>}  CURRENT_PROJECT_VERSION=${pbx_pv:-<unset>}"
        echo "  xcconfig:  MARKETING_VERSION=${xc_mv}  CURRENT_PROJECT_VERSION=${xc_pv}"
        echo "  Fix:       bash scripts/regen-all.sh"
        return 1
    fi

    echo "OK [${label}]: pbxproj override matches xcconfig (MARKETING_VERSION=${xc_mv}, CURRENT_PROJECT_VERSION=${xc_pv})."
    return 0
}

fail=0
check_one "Mac (public)" "$PUBLIC_MAC_PBX"  "$PUBLIC_XCCONFIG" || fail=1
if [ -n "$SIBLING" ] && [ -d "$SIBLING" ]; then
    check_one "Mac (private)" "$PRIVATE_MAC_PBX" "$PUBLIC_XCCONFIG" || fail=1
    check_one "iOS"           "$PRIVATE_IOS_PBX" "$IOS_XCCONFIG"    || fail=1
else
    echo "skip: no sibling repo provided (TERMURA_HARNESS_ROOT unset, Free build)."
fi

exit "$fail"
