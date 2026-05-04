#!/usr/bin/env bash
# CLAUDE.md §3.6 — iOS code mirroring cross-device state via CloudKit
# must wire BOTH a lifecycle re-pull (scenePhase=.active) AND a push
# subscription registration. The historical bug this gate exists to
# prevent: iOS had scenePhase but never registered a CloudKit
# subscription, so silent push never woke the app and mirrored state
# went stale until the user manually returned to the foreground.
#
# Heuristic project-level check:
#   - Skip if no CloudKit transport types appear in the tree (rule N/A
#     for LAN-only builds)
#   - Skip if any file carries the marker MIRROR-EXEMPT (explicit
#     opt-out for cases where pull-only is intentional)
#   - Otherwise require both:
#       a) at least one scenePhase reference (lifecycle re-request)
#       b) at least one push subscription marker
#          (CloudKitSubscriptionGateway type reference,
#           CKQuerySubscription / CKDatabaseSubscription /
#           CKRecordZoneSubscription, or register(targetDeviceId:))
#
# Usage: bash scripts/check-mirrored-state-freshness.sh [iOS_root]
# Default root: ./iOS — typically called from the public quality gate
# with the private repo's iOS directory.

set -euo pipefail

ROOT="${1:-./iOS}"

if [[ ! -d "$ROOT" ]]; then
    echo "OK: $ROOT does not exist; mirrored-state freshness check skipped"
    exit 0
fi

# Rule applies only when CloudKit transport is wired. LAN-only builds
# have no remote push channel at all and therefore no idle-staleness
# bug to defend against.
if ! grep -rq -E "CloudKitClientTransport|CloudKitDatabaseGateway" "$ROOT"; then
    echo "OK: No CloudKit transport detected under $ROOT; rule N/A"
    exit 0
fi

# Project-wide opt-out: a single MIRROR-EXEMPT annotation anywhere in
# the tree disables the gate. Use sparingly and document the reason
# in PR description.
if grep -rq "MIRROR-EXEMPT" "$ROOT"; then
    echo "OK: $ROOT carries MIRROR-EXEMPT marker (opted out)"
    exit 0
fi

ERRORS=0

if ! grep -rq "scenePhase" "$ROOT"; then
    echo "FAIL: CloudKit-using code under $ROOT has no scenePhase re-fetch hook."
    echo "      CLAUDE.md 3.6 requires a lifecycle re-request for mirrored remote state."
    echo "      Add an .onChange(of: scenePhase) handler that re-pulls on .active,"
    echo "      or annotate an exempt file with: // MIRROR-EXEMPT: <reason>"
    ERRORS=$((ERRORS + 1))
fi

if ! grep -rq -E "CloudKitSubscriptionGateway|CKQuerySubscription|CKDatabaseSubscription|CKRecordZoneSubscription|register\(targetDeviceId:" "$ROOT"; then
    echo "FAIL: CloudKit-using code under $ROOT has no push subscription registration."
    echo "      CLAUDE.md 3.6 requires push-on-change for mirrored remote state."
    echo "      Add a subscriptionGateway.register(targetDeviceId:) call from the"
    echo "      handshake / reconnect path, or annotate an exempt file with:"
    echo "      // MIRROR-EXEMPT: <reason>"
    ERRORS=$((ERRORS + 1))
fi

if [[ $ERRORS -eq 0 ]]; then
    echo "OK: $ROOT has both lifecycle and push freshness mechanisms"
    exit 0
fi
exit 1
