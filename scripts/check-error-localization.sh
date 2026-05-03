#!/usr/bin/env bash
# check-error-localization.sh
#
# Flags any `enum *Error: Error` declaration that doesn't also conform to
# `LocalizedError`. Without that conformance, `error.localizedDescription`
# falls back to Foundation's generic `"<Module>.<Type> error N."` shape,
# which is what surfaced "TermuraRemoteProtocol.CloudKitSubscriptionError
# error 0." in the Settings UI when CloudKit subscription registration
# failed (see CLAUDE.md §5.4).
#
# Rule: every Swift error enum that can flow to a UI surface must have
# either a direct `: LocalizedError` conformance or an extension adding
# `LocalizedError`. The check is conservative: any `enum *Error: Error...`
# declaration counts. If a particular enum is purely internal control flow
# and never surfaces, add it to `EXEMPT_ENUMS` below with a one-line reason.
#
# Usage:
#   ./scripts/check-error-localization.sh [scan_dir1] [scan_dir2] ...
#   With no args: scans Sources/ and Packages/ under the repo root.
#   Args may be relative to the repo root or absolute paths.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Enums that are intentionally exempt. Format: "EnumName:reason".
# Add entries sparingly — most exemptions should be fixed by adding
# LocalizedError conformance instead.
EXEMPT_ENUMS=(
)

SCAN_DIRS=()
if [[ $# -eq 0 ]]; then
    SCAN_DIRS=(
        "$REPO_ROOT/Sources"
        "$REPO_ROOT/Packages"
    )
else
    for arg in "$@"; do
        if [[ "$arg" = /* ]]; then
            SCAN_DIRS+=("$arg")
        else
            SCAN_DIRS+=("$REPO_ROOT/$arg")
        fi
    done
fi

is_exempt() {
    local name="$1"
    if [[ ${#EXEMPT_ENUMS[@]} -eq 0 ]]; then
        return 1
    fi
    for entry in "${EXEMPT_ENUMS[@]}"; do
        if [[ "${entry%%:*}" == "$name" ]]; then
            return 0
        fi
    done
    return 1
}

ERRORS=0
VIOLATIONS=""

# Collect every `enum X: ... Error...` declaration; rely on Swift naming
# convention (Error suffix) to avoid catching unrelated enums that happen
# to inherit `Error`. Multi-line declarations are supported by joining
# the line + the next line when the colon ends without a `{`.
collect_enum_decls() {
    local file="$1"
    awk '
        /^[[:space:]]*((public|internal|fileprivate|private)[[:space:]]+)?enum[[:space:]]+[A-Za-z_][A-Za-z0-9_]*Error[[:space:]]*:/ {
            print NR ":" $0
        }
    ' "$file"
}

for dir in "${SCAN_DIRS[@]}"; do
    [ -d "$dir" ] || continue

    while IFS= read -r -d '' file; do
        # Skip vendored / build artifact directories defensively.
        case "$file" in
            */.build/*|*/vendor/*|*/DerivedData/*) continue ;;
        esac

        rel_path="${file#"$REPO_ROOT/"}"

        while IFS= read -r decl_entry; do
            [[ -n "$decl_entry" ]] || continue
            lineno="${decl_entry%%:*}"
            content="${decl_entry#*:}"

            # Extract enum name. Pattern: `[modifier ]?enum <Name>...`.
            name="$(printf '%s' "$content" \
                | sed -E 's/.*enum[[:space:]]+([A-Za-z_][A-Za-z0-9_]*Error)[[:space:]]*:.*/\1/')"
            if [[ -z "$name" || "$name" == "$content" ]]; then
                continue
            fi

            if is_exempt "$name"; then
                continue
            fi

            # Already conforms inline?
            if printf '%s' "$content" | grep -q "LocalizedError"; then
                continue
            fi

            # Look across the whole repo for a matching extension that
            # adds LocalizedError. We only know the leaf type name, so we
            # accept either a bare `extension Name: LocalizedError` or a
            # qualified `extension Outer.Name: LocalizedError` form for
            # nested enums.
            if grep -rqE "extension[[:space:]]+([A-Za-z_][A-Za-z0-9_]*\.)*${name}[[:space:]]*:[^{]*LocalizedError" \
                --include="*.swift" "${SCAN_DIRS[@]}" 2>/dev/null; then
                continue
            fi

            VIOLATIONS="${VIOLATIONS}\n  ${rel_path}:${lineno}: ${name} is not LocalizedError"
            ERRORS=$((ERRORS + 1))
        done < <(collect_enum_decls "$file")

    done < <(find "$dir" -name "*.swift" -print0 2>/dev/null)
done

echo ""
echo "=== check-error-localization ==="

if [[ $ERRORS -gt 0 ]]; then
    echo "FAIL: $ERRORS error enum(s) missing LocalizedError conformance."
    echo ""
    echo "  Foundation's default localizedDescription for a non-LocalizedError"
    echo "  type renders as \"<Module>.<Type> error N.\" — opaque garbage to"
    echo "  the user. Conform the enum (directly or via extension):"
    echo ""
    echo "    extension MyError: LocalizedError {"
    echo "        var errorDescription: String? { ... }"
    echo "    }"
    echo ""
    echo "Violations:"
    echo -e "$VIOLATIONS"
    exit 1
fi

echo "OK: All Swift error enums conform to LocalizedError."
exit 0
