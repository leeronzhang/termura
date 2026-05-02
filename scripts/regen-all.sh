#!/usr/bin/env bash
# regen-all.sh — single entrypoint that re-generates every Xcode project
# this codebase touches, in dependency order. Use this instead of running
# `xcodegen generate` directly anywhere; missing one of the three pbxproj
# updates is the most common cause of "Cannot find <symbol> in scope"
# errors in this open-core split (public repo + sibling private repo).
#
# Modes:
#   regen-all.sh           regenerate everything, exit 0 on success
#   regen-all.sh --check   only verify each pbxproj is fresh; exit 1 on
#                          first staleness with the exact fix command.
#                          Used as an Xcode pre-build phase so a forgotten
#                          xcodegen run fails the build instead of
#                          silently producing a "missing symbol" link
#                          error 30 seconds later.
#
# Project map (each row = one yml → one pbxproj):
#   PUBLIC  project.yml                          → Termura.xcodeproj
#   PRIVATE <private repo>/project-mac.yml       → <private repo>/Termura-Mac.xcodeproj
#   PRIVATE <private repo>/iOS/project-ios.yml   → <private repo>/iOS/TermuraRemote.xcodeproj
#
# Private rows are skipped silently when the sibling private repo isn't
# present (Free build / clean clone), so this script is safe to run from
# any working tree.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS_ROOT="$(cd "$REPO_ROOT/.." && pwd)/termura-harness"
MODE="${1:-regen}"

declare -a TARGETS=(
    "$REPO_ROOT|project.yml|Termura.xcodeproj/project.pbxproj"
)
if [ -d "$HARNESS_ROOT" ]; then
    TARGETS+=(
        "$HARNESS_ROOT|project-mac.yml|Termura-Mac.xcodeproj/project.pbxproj"
        "$HARNESS_ROOT/iOS|project-ios.yml|TermuraRemote.xcodeproj/project.pbxproj"
    )
fi

color_red() { printf "\033[0;31m%s\033[0m\n" "$1"; }
color_green() { printf "\033[0;32m%s\033[0m\n" "$1"; }
color_yellow() { printf "\033[0;33m%s\033[0m\n" "$1"; }

regen_one() {
    local dir="$1" yml="$2" pbx="$3"
    if [ ! -f "$dir/$yml" ]; then
        color_yellow "skip: $dir/$yml not found"
        return 0
    fi
    ( cd "$dir" && xcodegen generate -s "$yml" )
}

# Returns 0 (fresh) / 1 (stale) / 2 (yml missing).
check_one() {
    local dir="$1" yml="$2" pbx="$3"
    local yml_path="$dir/$yml"
    local pbx_path="$dir/$pbx"
    [ -f "$yml_path" ] || return 2
    # Stale if pbxproj missing.
    [ -f "$pbx_path" ] || return 1
    # Stale if yml mtime > pbxproj mtime.
    if [ "$yml_path" -nt "$pbx_path" ]; then
        return 1
    fi
    # Stale if any tracked source file under one of the yml's `sources:`
    # roots has a basename that doesn't appear in the pbxproj. We don't
    # parse YAML — instead we sweep the well-known source roots used by
    # this repo. Cheap and good enough.
    local roots
    # Roots compiled DIRECTLY into the target (not via SwiftPM resolution).
    # Files under a package (e.g. `Packages/TermuraRemoteKit/Sources/`) are
    # owned by Package.swift and never appear in the main pbxproj — adding
    # them to this list produces false-positive STALE reports.
    case "$yml" in
        project.yml)
            roots=("Sources/Termura" "Sources/TermuraNotesKit")
            ;;
        project-mac.yml)
            roots=("Sources" "../termura/Sources/Termura" "../termura/Sources/TermuraNotesKit")
            ;;
        project-ios.yml)
            roots=("TermuraRemote")
            ;;
        *)
            roots=()
            ;;
    esac
    for root in "${roots[@]}"; do
        local abs="$dir/$root"
        [ -d "$abs" ] || continue
        # `find` then check basename presence in pbxproj. We compare on
        # basename rather than path because xcodegen records `path = "x.swift"`.
        while IFS= read -r -d '' swift; do
            local base
            base="$(basename "$swift")"
            if ! grep -qF "$base" "$pbx_path"; then
                return 1
            fi
        done < <(find "$abs" -name '*.swift' -print0 2>/dev/null)
    done
    return 0
}

if [ "$MODE" = "--check" ]; then
    any_stale=0
    for row in "${TARGETS[@]}"; do
        IFS='|' read -r dir yml pbx <<< "$row"
        if check_one "$dir" "$yml" "$pbx"; then
            color_green "fresh: $dir/$yml → $pbx"
        else
            rc=$?
            if [ "$rc" = "2" ]; then
                color_yellow "skip:  $dir/$yml not present"
                continue
            fi
            color_red "STALE: $dir/$yml → $pbx"
            any_stale=1
        fi
    done
    if [ "$any_stale" = "1" ]; then
        echo ""
        color_red "One or more Xcode projects are out of sync with disk."
        echo "Fix:  bash $REPO_ROOT/scripts/regen-all.sh"
        exit 1
    fi
    exit 0
fi

# Default mode: regenerate every project, in order.
echo "regen-all: regenerating $(echo "${#TARGETS[@]}") project(s)…"
for row in "${TARGETS[@]}"; do
    IFS='|' read -r dir yml pbx <<< "$row"
    color_green "→ $dir/$yml"
    regen_one "$dir" "$yml" "$pbx"
done
echo ""
color_green "regen-all: done. Now ⌘Q Xcode and reopen the workspace if it was open."
