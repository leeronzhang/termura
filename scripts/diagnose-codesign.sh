#!/usr/bin/env bash
#
# diagnose-codesign.sh — Diagnose and (optionally) repair Termura codesign failures.
#
# Common failure: "Termura.app: Operation not permitted" during CodeSign phase.
# Root causes addressed by this script:
#   1. Stale com.apple.quarantine / com.apple.provenance xattrs on .app or its
#      copied resources, which codesign refuses to seal.
#   2. DerivedData artifacts left over from a crashed/interrupted build that
#      hold file locks or have inconsistent signatures.
#
# What this script DOES NOT touch:
#   - Resources/Termura.entitlements, project.yml, vendor/ submodules.
#   - Apple Developer Portal config (entitlements ↔ capability sync).
#   - Code signing identities or keychain.
#
# Usage:
#   bash scripts/diagnose-codesign.sh              # apply fixes
#   bash scripts/diagnose-codesign.sh --dry-run    # only print actions

set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

strip_xattrs() {
    local target="$1"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] xattr -cr $target"
    else
        xattr -cr "$target"
        echo "  cleaned: $target"
    fi
}

clear_dir() {
    local target="$1"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] rm -rf $target"
    else
        rm -rf "$target"
        echo "  removed: $target"
    fi
}

echo "==> 1/5  Check Xcode is closed (avoids file locks)"
if pgrep -x Xcode >/dev/null 2>&1; then
    echo "  WARN: Xcode is running. Quit it before re-running this script."
    echo "  (Continuing with read-only steps; cleanup will be skipped.)"
    XCODE_RUNNING=1
else
    echo "  OK"
    XCODE_RUNNING=0
fi

echo "==> 2/5  Strip xattrs from project resources (provenance/quarantine)"
for path in Resources vendor/ghostty-resources; do
    [[ -d "$path" ]] || continue
    strip_xattrs "$path"
done

echo "==> 3/5  Strip xattrs from built .app bundles in DerivedData"
shopt -s nullglob
DERIVED_DIRS=("$HOME/Library/Developer/Xcode/DerivedData"/Termura-*)
APP_PATHS=()
for dd in "${DERIVED_DIRS[@]}"; do
    while IFS= read -r app; do
        APP_PATHS+=("$app")
    done < <(find "$dd/Build/Products" -maxdepth 3 -type d -name "Termura.app" 2>/dev/null)
done
shopt -u nullglob
if [[ ${#APP_PATHS[@]} -eq 0 ]]; then
    echo "  (no built .app found, skipping)"
else
    for app in "${APP_PATHS[@]}"; do
        strip_xattrs "$app"
    done
fi

echo "==> 4/5  Clear Termura DerivedData (forces clean re-sign)"
if [[ $XCODE_RUNNING -eq 1 ]]; then
    echo "  SKIP: Xcode is running. Quit Xcode first."
elif [[ ${#DERIVED_DIRS[@]} -eq 0 ]]; then
    echo "  (no DerivedData entries to clear)"
else
    for dd in "${DERIVED_DIRS[@]}"; do
        clear_dir "$dd"
    done
fi

echo "==> 5/5  TCC permission hint"
echo "  If failures persist, ensure Xcode has these macOS permissions:"
echo "    System Settings → Privacy & Security → Developer Tools  → Xcode (ON)"
echo "    System Settings → Privacy & Security → Full Disk Access → Xcode (ON)"
echo "  (Cannot be set programmatically; user must grant in Settings.)"

echo
echo "Done. Now re-open Xcode and Cmd+R."
echo "If 'Operation not permitted' persists, check the codesign sub-error in"
echo "the Xcode Report navigator (cmd+9) and re-run with --dry-run to share output."
