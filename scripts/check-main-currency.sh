#!/usr/bin/env bash
#
# scripts/check-main-currency.sh
#
# CLAUDE.md §15.6 — "main currency" audit. Reports the state of main vs every
# published branch in the public repo (and the sibling private repo if
# present). Pure inspector — never modifies refs.
#
# Sibling discovery is environment-driven (TERMURA_HARNESS_ROOT) so this
# script never embeds the private repo path literal. See CLAUDE.md §12.3 for
# the open-core baseline rules that motivate this indirection.
#
# What it reports:
#   1. main HEAD vs origin/main, plus working-tree cleanliness.
#   2. Each published branch's relation to main:
#        merged         — already in main; safe to delete locally.
#        ff-pending     — main is ancestor; one `git merge --ff-only` away.
#        diverged       — branches share an ancestor but main moved on; needs
#                         cherry-pick / --no-ff merge / rebase decision.
#      Each branch's tip commit age (days since author commit).
#   3. Cross-repo wire coordination: every TermuraRemoteProtocol type
#      referenced by the private repo's iOS sources must exist in the public
#      repo's main, else the next private merge will break the iOS build
#      (see CLAUDE.md §15.2).
#
# Branch naming convention (noise control):
#   archive/*  Intentionally retained snapshot; never reported as stale,
#              regardless of age.
#   wip/*      Active long-lived work; not yet a merge candidate.
#   ready/*    Author has declared the branch complete and awaiting merge;
#              staleness threshold tightens (READY_STALE_DAYS).
#   *          Default merge candidate; flagged once age >= STALE_DAYS.
#
# Usage:
#   bash scripts/check-main-currency.sh           # advisory, always exit 0
#   bash scripts/check-main-currency.sh --strict  # exit 1 on stale branches
#                                                   or cross-repo wire drift
#   bash scripts/check-main-currency.sh --quiet   # suppress per-branch table,
#                                                   keep summary + warnings
#
# Tunables (env vars):
#   STALE_DAYS=3        Age threshold for default branches.
#   READY_STALE_DAYS=1  Tighter age threshold for ready/* branches.
#   TERMURA_HARNESS_ROOT=...  Absolute path of the sibling private iOS repo.
#                       Set this in your shell rc; the script does no path
#                       discovery on its own so the open-core boundary stays
#                       free of sibling-name literals (§12.3).

set -euo pipefail

STRICT=0
QUIET=0
SKIP_WIRE=0
for arg in "$@"; do
    case "$arg" in
        --strict)  STRICT=1 ;;
        --quiet)   QUIET=1 ;;
        --no-wire) SKIP_WIRE=1 ;;
        -h|--help)
            sed -n '2,/^set -euo/{/^set -euo/d; s/^# \{0,1\}//; p;}' "$0"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--strict] [--quiet] [--no-wire]" >&2
            exit 2
            ;;
    esac
done

STALE_DAYS="${STALE_DAYS:-3}"
READY_STALE_DAYS="${READY_STALE_DAYS:-1}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
DIM='\033[2m'
NC='\033[0m'

PUBLIC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIVATE_ROOT="${TERMURA_HARNESS_ROOT:-}"
if [[ -n "$PRIVATE_ROOT" && ! -d "$PRIVATE_ROOT/.git" ]]; then
    echo "warn: TERMURA_HARNESS_ROOT=$PRIVATE_ROOT is not a git repo; ignoring." >&2
    PRIVATE_ROOT=""
fi

STALE_COUNT=0
WIRE_DRIFT_COUNT=0

# Print a label/value line. Used for the per-repo header block.
hdr() {
    printf '  %-26s %s\n' "$1" "$2"
}

# Classify the branch name into a noise-control bucket.
branch_class() {
    case "$1" in
        archive/*) echo "archive" ;;
        wip/*)     echo "wip" ;;
        ready/*)   echo "ready" ;;
        *)         echo "default" ;;
    esac
}

# Days between the branch tip's author commit and now. Uses author date so a
# rebase doesn't reset "age" — what matters is when the work was written.
branch_age_days() {
    local repo="$1"
    local ref="$2"
    local ts
    ts="$(git -C "$repo" log -1 --format=%at "$ref" 2>/dev/null || echo 0)"
    if [[ "$ts" == "0" ]]; then
        echo "?"
        return
    fi
    local now
    now="$(date +%s)"
    echo $(( (now - ts) / 86400 ))
}

# Classify branch's relation to main.
#   merged     = every commit in branch is present in main, either by ancestry
#                or by patch-id equivalence (cherry-picked / rebased in).
#   ff-pending = main is ancestor of branch (linear, ff-mergeable).
#   diverged   = at least one commit on branch is patch-id-novel AND main
#                isn't an ancestor of the branch.
branch_relation() {
    local repo="$1"
    local ref="$2"
    # `git cherry main <ref>` prints one line per commit:
    #   '+ <sha>' if the patch isn't in main, '- <sha>' if patch-id matches
    #   something in main already. No '+' lines == fully merged.
    if ! git -C "$repo" cherry main "$ref" 2>/dev/null | grep -q '^+'; then
        echo "merged"
    elif git -C "$repo" merge-base --is-ancestor main "$ref" 2>/dev/null; then
        echo "ff-pending"
    else
        echo "diverged"
    fi
}

# Per-repo report. Outputs the main HEAD line, working tree status, and the
# per-branch matrix. Updates STALE_COUNT for the strict gate.
audit_repo() {
    local repo="$1"
    local label="$2"

    echo ""
    echo "[Repo: ${label}]"
    if [[ ! -d "$repo/.git" ]]; then
        echo "  (no .git directory — skipped)"
        return
    fi

    local head_sha tracking_state worktree_state
    head_sha="$(git -C "$repo" rev-parse --short main 2>/dev/null || echo '?')"
    if git -C "$repo" rev-parse --verify origin/main >/dev/null 2>&1; then
        local local_main remote_main
        local_main="$(git -C "$repo" rev-parse main)"
        remote_main="$(git -C "$repo" rev-parse origin/main)"
        if [[ "$local_main" == "$remote_main" ]]; then
            tracking_state="in sync with origin/main"
        else
            local ahead behind
            ahead="$(git -C "$repo" rev-list --count origin/main..main 2>/dev/null || echo 0)"
            behind="$(git -C "$repo" rev-list --count main..origin/main 2>/dev/null || echo 0)"
            tracking_state="ahead ${ahead} / behind ${behind} vs origin/main"
        fi
    else
        tracking_state="no origin/main configured"
    fi

    if [[ -z "$(git -C "$repo" status --porcelain)" ]]; then
        worktree_state="clean"
    else
        local dirty
        dirty="$(git -C "$repo" status --porcelain | wc -l | tr -d ' ')"
        worktree_state="${dirty} file(s) dirty"
    fi

    hdr "main HEAD" "${head_sha}  (${tracking_state})"
    hdr "Working tree" "${worktree_state}"

    # Enumerate all branches: local + remote (origin/*), de-duplicated by
    # short name. main itself is skipped. HEAD pseudo-ref is skipped.
    local refs
    refs="$(
        {
            git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads
            # Only well-formed origin/<branch> refs; rejects degenerate refs
            # like a bare `origin` pseudo-entry and `origin/HEAD` pointer.
            git -C "$repo" for-each-ref --format='%(refname:short)' refs/remotes/origin |
                grep -E '^origin/[^/]' |
                grep -v '^origin/HEAD$' |
                sed 's|^origin/||'
        } | grep -vE '^(HEAD|main)$' | sort -u
    )"

    local merged_lines="" pending_lines="" diverged_lines=""
    local branch class age rel resolved_ref
    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue
        # Prefer local ref; fall back to origin/<branch> if local doesn't exist.
        if git -C "$repo" rev-parse --verify "refs/heads/$branch" >/dev/null 2>&1; then
            resolved_ref="$branch"
        else
            resolved_ref="origin/$branch"
        fi
        class="$(branch_class "$branch")"
        age="$(branch_age_days "$repo" "$resolved_ref")"
        rel="$(branch_relation "$repo" "$resolved_ref")"

        local age_decoration="" stale=0
        if [[ "$rel" != "merged" && "$age" != "?" ]]; then
            case "$class" in
                archive|wip) ;;
                ready)
                    if (( age >= READY_STALE_DAYS )); then stale=1; fi
                    ;;
                default)
                    if (( age >= STALE_DAYS )); then stale=1; fi
                    ;;
            esac
            if (( stale == 1 )); then
                age_decoration=" ⚠ stale"
                STALE_COUNT=$((STALE_COUNT + 1))
            fi
        fi

        local line
        line="$(printf '    %-44s %-10s %3s d%s' "$branch" "[$class]" "$age" "$age_decoration")"
        case "$rel" in
            merged)     merged_lines+="${line}"$'\n' ;;
            ff-pending) pending_lines+="${line}"$'\n' ;;
            diverged)   diverged_lines+="${line}"$'\n' ;;
        esac
    done <<< "$refs"

    if (( QUIET == 1 )); then
        return
    fi

    if [[ -n "$pending_lines" ]]; then
        echo "  Branches NOT merged → main (ff-mergeable):"
        printf '%b' "$pending_lines"
    fi
    if [[ -n "$diverged_lines" ]]; then
        echo "  Branches NOT merged → main (diverged — needs strategy):"
        printf '%b' "$diverged_lines"
    fi
    if [[ -z "$pending_lines" && -z "$diverged_lines" ]]; then
        echo "  Branches NOT merged → main: (none)"
    fi
    if [[ -n "$merged_lines" ]]; then
        echo -e "  ${DIM}Branches already merged (备份保留):${NC}"
        printf '%b' "$merged_lines" | sed "s/^/$(printf '%b' "${DIM}")/" | sed "s/$/$(printf '%b' "${NC}")/"
    fi
}

# Cross-repo wire coordination. For every wire-shaped type referenced by the
# private iOS sources, verify some public source under Packages/ declares it.
# The detector is naming-pattern based, not type-resolution based: any symbol
# whose name suggests a wire role (matches WIRE_NAME_PAT) that the private
# code mentions but the public Packages tree doesn't declare is flagged.
# False positives end up flagged when a private-only iOS type happens to fit
# the naming pattern — that's an acceptable tradeoff for the failure mode it
# catches (§15.2: private references a wire type that public main has yet to
# ship, breaking the iOS SPM build on the next private main merge).
audit_wire() {
    if [[ -z "$PRIVATE_ROOT" ]]; then
        return
    fi
    local private_ios="$PRIVATE_ROOT/iOS"
    local pkg_dir="$PUBLIC_ROOT/Packages"
    if [[ ! -d "$private_ios" || ! -d "$pkg_dir" ]]; then
        return
    fi

    echo ""
    echo "[Cross-repo wire coordination]"

    local importers
    importers="$(grep -rlE '^import TermuraRemoteProtocol' "$private_ios" 2>/dev/null || true)"
    if [[ -z "$importers" ]]; then
        echo "  No private iOS files import TermuraRemoteProtocol — nothing to check."
        return
    fi

    # Names that look like a wire type. Pattern is "any capitalized
    # identifier whose stem contains one of these wire-flavoured infixes".
    local wire_name_pat='[A-Z][A-Za-z0-9_]*(Envelope|Gateway|Pairing|Pairable|Paired|Reconnect|Subscription|Handshake|PairKey|CipherDecode|Bonjour|CloudKit|DeviceIdentity|PairComplete)[A-Za-z0-9_]*'

    # Pre-compute the set of types declared anywhere we'd consider "defined":
    # two grep -rh passes (public Packages/ + private iOS/), then a single
    # `comm` does the set difference. Avoids per-symbol grep loops that
    # quickly blow up when there are hundreds of referenced symbols.
    local decl_extract='s/.*(struct|enum|class|protocol|typealias|actor) ([A-Z][A-Za-z0-9_]+).*/\2/'
    local decl_file ref_file
    decl_file="$(mktemp)"
    ref_file="$(mktemp)"
    trap 'rm -f "$decl_file" "$ref_file"' RETURN

    {
        grep -rhE --include='*.swift' "(struct|enum|class|protocol|typealias|actor) [A-Z][A-Za-z0-9_]+" \
            "$pkg_dir" 2>/dev/null
        grep -rhE --include='*.swift' "(struct|enum|class|protocol|typealias|actor) [A-Z][A-Za-z0-9_]+" \
            "$private_ios" 2>/dev/null
    } | sed -E "$decl_extract" | LC_ALL=C sort -u > "$decl_file"

    # shellcheck disable=SC2086
    grep -hoE "\\b${wire_name_pat}\\b" $importers 2>/dev/null |
        LC_ALL=C sort -u > "$ref_file"

    # comm -23 = lines only in ref_file (= referenced but not declared).
    local missing missing_count
    missing="$(LC_ALL=C comm -23 "$ref_file" "$decl_file" | sed 's/^/    /')"
    if [[ -n "$missing" ]]; then
        missing_count="$(printf '%s\n' "$missing" | grep -c .)"
    else
        missing_count=0
    fi

    if (( missing_count > 0 )); then
        WIRE_DRIFT_COUNT=$((WIRE_DRIFT_COUNT + missing_count))
        echo -e "  ${YELLOW}Wire types referenced by private iOS but absent from public Packages/:${NC}"
        printf '%s\n' "$missing"
        echo "  → Public main must add these before private main merges (§15.2)."
    else
        echo -e "  ${GREEN}OK${NC}: every wire-shaped private reference is declared in public Packages/."
    fi
}

audit_repo "$PUBLIC_ROOT"  "public repo (Mac)"
if [[ -n "$PRIVATE_ROOT" ]]; then
    audit_repo "$PRIVATE_ROOT" "private repo (iOS Remote)"
fi
if (( SKIP_WIRE == 0 )); then
    audit_wire
fi

echo ""
echo "======================================"
if (( STALE_COUNT == 0 && WIRE_DRIFT_COUNT == 0 )); then
    echo -e "${GREEN}OK: main is current; no stale published branches and no wire drift.${NC}"
    exit 0
fi

echo -e "${YELLOW}Findings: ${STALE_COUNT} stale branch(es), ${WIRE_DRIFT_COUNT} wire drift(s).${NC}"
echo "  Stale = published & non-archive/non-wip, age above threshold."
echo "  Mark a branch with the 'archive/' prefix (rename it) to silence the"
echo "  warning when retention is intentional."
if (( STRICT == 1 )); then
    exit 1
fi
exit 0
