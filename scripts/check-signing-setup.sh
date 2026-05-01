#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_YML="${REPO_ROOT}/project.yml"
PBXPROJ="${REPO_ROOT}/Termura.xcodeproj/project.pbxproj"

if [[ ! -f "$PROJECT_YML" ]]; then
    echo "WARN: project.yml not found. Copy project.yml.example to project.yml first."
    exit 3
fi

if ! command -v security >/dev/null 2>&1; then
    echo "WARN: security tool not available; skipping local signing check."
    exit 3
fi

TEAM_ID="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$PROJECT_YML" | head -1)"
if [[ -z "$TEAM_ID" ]]; then
    echo "FAIL: DEVELOPMENT_TEAM is missing from project.yml."
    exit 1
fi

if [[ "$TEAM_ID" == "REPLACE_WITH_YOUR_TEAM_ID" ]]; then
    echo "FAIL: DEVELOPMENT_TEAM in project.yml is still the template placeholder."
    exit 1
fi

set +e
IDENTITIES="$(security find-identity -p codesigning -v 2>&1)"
IDENTITY_STATUS=$?
set -e
if [[ $IDENTITY_STATUS -ne 0 ]]; then
    echo "WARN: Unable to query local code-signing identities via Keychain."
    echo "  Details: ${IDENTITIES}"
    exit 3
fi

if ! grep -Eq "Apple Development: .+\\(${TEAM_ID}\\)" <<<"$IDENTITIES"; then
    echo "FAIL: No Apple Development signing identity found for team ${TEAM_ID}."
    echo "Available Apple Development identities:"
    grep "Apple Development:" <<<"$IDENTITIES" || echo "  (none)"
    exit 1
fi

if [[ -f "$PBXPROJ" ]]; then
    PBX_TEAM_ID="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM = \([^;]*\);[[:space:]]*$/\1/p' "$PBXPROJ" | head -1)"
    if [[ -n "$PBX_TEAM_ID" && "$PBX_TEAM_ID" != "$TEAM_ID" ]]; then
        echo "FAIL: Termura.xcodeproj still uses DEVELOPMENT_TEAM=${PBX_TEAM_ID}, but project.yml uses ${TEAM_ID}."
        echo "Fix: run 'xcodegen generate' to regenerate the project."
        exit 1
    fi
fi

# Debug entitlements stub must exist — project.yml's Debug config references
# Resources/TermuraDebug.entitlements; missing it breaks ad-hoc Debug signing.
DEBUG_ENT="${REPO_ROOT}/Resources/TermuraDebug.entitlements"
if [[ ! -f "$DEBUG_ENT" ]]; then
    echo "FAIL: Resources/TermuraDebug.entitlements is missing (referenced by project.yml Debug config)."
    echo "Fix: 'git checkout Resources/TermuraDebug.entitlements' or recreate as an empty <plist><dict/></plist>."
    exit 1
fi

# Runtime check: stale com.apple.quarantine on built .app causes
# "Operation not permitted" during CodeSign. Warn (don't fail) and point to
# scripts/diagnose-codesign.sh for cleanup.
SIGNING_WARN=0
shopt -s nullglob
for dd in "$HOME/Library/Developer/Xcode/DerivedData"/Termura-*; do
    while IFS= read -r app; do
        if xattr "$app" 2>/dev/null | grep -q com.apple.quarantine; then
            echo "WARN: quarantine xattr on built bundle: $app"
            SIGNING_WARN=1
        fi
    done < <(find "$dd/Build/Products" -maxdepth 3 -type d -name "Termura.app" 2>/dev/null)
done
shopt -u nullglob

# Source resources rarely carry quarantine, but if they do, codesign will
# also reject them. provenance is benign and intentionally not flagged.
for path in "${REPO_ROOT}/Resources" "${REPO_ROOT}/vendor/ghostty-resources"; do
    [[ -d "$path" ]] || continue
    if find "$path" -type f -exec xattr {} \; 2>/dev/null | grep -q com.apple.quarantine; then
        echo "WARN: com.apple.quarantine found under ${path#${REPO_ROOT}/}"
        SIGNING_WARN=1
    fi
done

if [[ $SIGNING_WARN -eq 1 ]]; then
    echo "  Hint: run 'bash scripts/diagnose-codesign.sh' to clean."
fi

echo "OK: Signing setup matches local Apple Development identity for team ${TEAM_ID}."
