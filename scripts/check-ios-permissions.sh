#!/usr/bin/env bash
# iOS App Store submission gate. Catches the seven classes of permission /
# privacy / capability issues that flagged the 2026-05 audit:
#
#   1. NS*UsageDescription declared in Info.plist without a matching API call
#      → App Review 5.1.1(i) reject
#   2. LAContext.evaluatePolicy used without NSFaceIDUsageDescription
#      → runtime crash on Face ID devices
#   3. aps-environment, IF declared in entitlements, must be "development"
#      (Xcode archive flow re-signs with production from the provisioning
#      profile). The previous incarnation banned the key outright; that
#      mis-led an audit fix into deleting it and breaking silent push.
#   4. Required Reason API used (UserDefaults / file timestamp / boot time /
#      disk space / active keyboards) without PrivacyInfo.xcprivacy
#      → ITMS upload reject (Apple enforced since 2024-05-01)
#   5. UIBackgroundModes ↔ entitlement / plist-key consistency:
#        remote-notification ⇒ aps-environment must exist
#        processing         ⇒ BGTaskSchedulerPermittedIdentifiers must exist
#      Was the missing rule that allowed P0-4 to slip past review.
#   6. Reverse usage-description: every API pattern in USAGE_API_TABLE that
#      is actually called from source MUST have its NS*UsageDescription
#      declared in Info.plist (catches "added LAContext, forgot the key").
#   7. AppIcon completeness: either Xcode 14+ single-size universal 1024×1024
#      mode (one PNG, correct Contents.json) or a full traditional idiom
#      set. Catches an empty / wrong-dimensioned icon set before ITMS does.
#
# Scope: the private iOS app subtree at $IOS_HARNESS_ROOT/iOS/TermuraRemote.
# Mac builds bypass App Store and have separate distribution rules.
#
# Exit codes: 0 = pass, 1 = fail (blocking).
#
# Implementation note: avoids bash 4 associative arrays so it runs on the
# macOS default bash 3.2 without forcing `brew install bash`.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLIC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# IOS_HARNESS_ROOT is supplied explicitly by the caller (quality-gate.sh sets
# it from its own --include-private resolution). No literal sibling-path
# fallback here: hardcoding the private repo's relative path would trip the
# open-core leak scan (CLAUDE.md §12.3, LEAK_PATTERN is path-only). When the
# caller omits the env var the gate is a no-op (Free build).
HARNESS_ROOT="${IOS_HARNESS_ROOT:-}"
IOS_APP_ROOT="${HARNESS_ROOT:+$HARNESS_ROOT/iOS/TermuraRemote}"
INFO_PLIST="$IOS_APP_ROOT/Resources/Info.plist"
ENTITLEMENTS="$IOS_APP_ROOT/Resources/TermuraRemote.entitlements"
PRIVACY_MANIFEST="$IOS_APP_ROOT/Resources/PrivacyInfo.xcprivacy"
APPICON_SET="$IOS_APP_ROOT/Resources/Assets.xcassets/AppIcon.appiconset"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

ERRORS=0

if [[ -z "$IOS_APP_ROOT" || ! -d "$IOS_APP_ROOT" ]]; then
    # Free build (caller did not pass IOS_HARNESS_ROOT, or the iOS app
    # subtree is absent) — gate is a no-op so the public quality gate stays
    # green. The private wrapper invokes us with the env var set.
    if [[ -z "$IOS_APP_ROOT" ]]; then
        echo -e "${YELLOW}SKIP: IOS_HARNESS_ROOT not set (Free build).${NC}"
    else
        echo -e "${YELLOW}SKIP: iOS app not found at $IOS_APP_ROOT (Free build).${NC}"
    fi
    exit 0
fi

if [[ ! -f "$INFO_PLIST" ]]; then
    echo -e "${RED}FAIL: Info.plist missing at $INFO_PLIST${NC}"
    exit 1
fi

# ---------- shared tables ----------------------------------------------------
# Format: one "key|grep-pattern" per line. Keep alphabetised within blocks.
USAGE_API_TABLE=$(cat <<'EOF'
NSCameraUsageDescription|AVCaptureSession|AVCaptureDevice|DataScannerViewController|VNDetectBarcodes|UIImagePickerController.*camera|AVCaptureMetadataOutput
NSPhotoLibraryUsageDescription|PHPhotoLibrary|PHPickerViewController|UIImagePickerController.*photoLibrary
NSPhotoLibraryAddUsageDescription|PHPhotoLibrary.*performChanges|UIImageWriteToSavedPhotosAlbum
NSMicrophoneUsageDescription|AVAudioSession|AVAudioRecorder|AVCaptureDevice.*audio
NSLocationWhenInUseUsageDescription|CLLocationManager|requestWhenInUseAuthorization|startUpdatingLocation
NSLocationAlwaysAndWhenInUseUsageDescription|requestAlwaysAuthorization
NSContactsUsageDescription|CNContactStore|CNContact
NSCalendarsUsageDescription|EKEventStore|EKEvent
NSRemindersUsageDescription|EKEventStore.*reminder
NSBluetoothAlwaysUsageDescription|CBCentralManager|CBPeripheralManager
NSMotionUsageDescription|CMMotionManager|CMPedometer|CMAltimeter
NSHealthShareUsageDescription|HKHealthStore.*requestAuthorization|HKQuery
NSHealthUpdateUsageDescription|HKHealthStore.*save
NSFaceIDUsageDescription|LAContext|evaluatePolicy.*deviceOwnerAuthenticationWithBiometrics
NSLocalNetworkUsageDescription|NWBrowser|NWConnection|NWParameters|NWListener|NetService|Bonjour
NSUserTrackingUsageDescription|ATTrackingManager|requestTrackingAuthorization
NSSpeechRecognitionUsageDescription|SFSpeechRecognizer
NSSiriUsageDescription|INPreferences.*requestSiriAuthorization|INVocabulary
NSAppleMusicUsageDescription|MPMediaQuery|MPMusicPlayerController
NSHomeKitUsageDescription|HMHomeManager|HMAccessory
EOF
)

# Sources that may host APIs backing the iOS app's declared usage strings.
# E.g. NSLocalNetworkUsageDescription is satisfied by NWBrowser inside
# TermuraRemoteKit, not the iOS target itself.
SCAN_PATHS="$IOS_APP_ROOT"
if [[ -d "$PUBLIC_ROOT/Packages/TermuraRemoteKit/Sources" ]]; then
    SCAN_PATHS="$IOS_APP_ROOT $PUBLIC_ROOT/Packages/TermuraRemoteKit/Sources"
fi

DECLARED_USAGES=$(/usr/bin/plutil -p "$INFO_PLIST" 2>/dev/null \
    | grep -oE 'NS[A-Z][a-zA-Z]+UsageDescription' | sort -u)

# Returns "1" if grep pattern matches anywhere in SCAN_PATHS Swift sources.
api_used_in_sources() {
    local pattern="$1"
    if grep -rEq "$pattern" --include='*.swift' $SCAN_PATHS 2>/dev/null; then
        echo "1"
    else
        echo "0"
    fi
}

# Returns "1" if Info.plist declares the given key.
plist_has_key() {
    local key="$1"
    /usr/bin/plutil -extract "$key" raw -o - "$INFO_PLIST" >/dev/null 2>&1
}

# ---------- 1. Usage Description ↔ real API call -----------------------------

if [[ -z "$DECLARED_USAGES" ]]; then
    echo -e "${GREEN}OK: No NS*UsageDescription declared (nothing to validate).${NC}"
else
    echo "-> Validating usage description(s) against source..."
    while IFS= read -r usage; do
        [[ -n "$usage" ]] || continue
        row=$(echo "$USAGE_API_TABLE" | grep -E "^${usage}\|" || true)
        if [[ -z "$row" ]]; then
            echo -e "  ${YELLOW}WARN${NC}: $usage has no known API pattern (extend USAGE_API_TABLE in $0)."
            continue
        fi
        pattern="${row#${usage}|}"
        if [[ "$(api_used_in_sources "$pattern")" == "1" ]]; then
            echo -e "  ${GREEN}OK${NC}: $usage → matched in source"
        else
            echo -e "  ${RED}FAIL${NC}: $usage declared in Info.plist but no matching API call found"
            echo "         pattern: $pattern"
            echo "         scanned: $SCAN_PATHS"
            echo "         fix: remove the key from $INFO_PLIST or implement the API"
            ERRORS=$((ERRORS + 1))
        fi
    done <<< "$DECLARED_USAGES"
fi

# ---------- 2. LAContext ↔ NSFaceIDUsageDescription --------------------------

if grep -rEq 'LAContext|evaluatePolicy' --include='*.swift' "$IOS_APP_ROOT" 2>/dev/null; then
    if ! plist_has_key NSFaceIDUsageDescription; then
        echo -e "${RED}FAIL${NC}: LAContext used without NSFaceIDUsageDescription"
        echo "       LAContext.evaluatePolicy crashes the process on Face ID devices"
        echo "       without this key. Add to $INFO_PLIST."
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  ${GREEN}OK${NC}: LAContext usage paired with NSFaceIDUsageDescription"
    fi
fi

# ---------- 3. aps-environment value sanity ---------------------------------

if [[ -f "$ENTITLEMENTS" ]]; then
    aps_value="$(/usr/bin/plutil -extract 'aps-environment' raw -o - "$ENTITLEMENTS" 2>/dev/null || true)"
    if [[ -n "$aps_value" ]]; then
        if [[ "$aps_value" == "development" ]]; then
            echo -e "  ${GREEN}OK${NC}: aps-environment=development (codesign re-signs Release as production)"
        else
            echo -e "${RED}FAIL${NC}: aps-environment in $ENTITLEMENTS is \"$aps_value\""
            echo "       Must be \"development\". Xcode archive flow re-signs distribution"
            echo "       builds with the production value from the provisioning profile."
            ERRORS=$((ERRORS + 1))
        fi
    fi
fi

# ---------- 4. Required Reason API → PrivacyInfo.xcprivacy required ----------
REQUIRED_REASON_TABLE=$(cat <<'EOF'
UserDefaults|UserDefaults\(|UserDefaults\.standard|@AppStorage|NSUserDefaults
FileTimestamp|\.fileCreationDate|\.fileModificationDate|attributesOfItem|getResourceValue.*creationDate|getResourceValue.*contentModificationDate
SystemBootTime|ProcessInfo\.processInfo\.systemUptime|kern\.boottime|mach_absolute_time
DiskSpace|volumeAvailableCapacity|systemFreeSize|NSFileSystemFreeSize
ActiveKeyboards|UITextInputMode\.activeInputModes
EOF
)

USES_REQUIRED_REASON_API=0
TRIGGERED_REASONS=""
while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    category="${row%%|*}"
    pattern="${row#${category}|}"
    if grep -rEq "$pattern" --include='*.swift' "$IOS_APP_ROOT" 2>/dev/null; then
        USES_REQUIRED_REASON_API=1
        TRIGGERED_REASONS="$TRIGGERED_REASONS $category"
    fi
done <<< "$REQUIRED_REASON_TABLE"

if [[ $USES_REQUIRED_REASON_API -eq 1 ]]; then
    if [[ ! -f "$PRIVACY_MANIFEST" ]]; then
        echo -e "${RED}FAIL${NC}: Required Reason APIs used but PrivacyInfo.xcprivacy missing"
        echo "       Categories triggered:$TRIGGERED_REASONS"
        echo "       Apple enforces this since 2024-05-01 (ITMS upload reject)."
        echo "       Create $PRIVACY_MANIFEST."
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  ${GREEN}OK${NC}: PrivacyInfo.xcprivacy exists for categories:$TRIGGERED_REASONS"
    fi
fi

# ---------- 5. UIBackgroundModes ↔ companion-key consistency -----------------
# Each declared background mode pulls in a partner artifact that must also
# exist; missing the partner means the runtime registration silently fails
# (e.g. APNs device-token request never returns) and the feature is dead.

ENABLED_BG_MODES=$(/usr/bin/plutil -extract 'UIBackgroundModes' json -o - "$INFO_PLIST" 2>/dev/null \
    | python3 -c 'import sys, json
try:
    items = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(items, list):
    for item in items:
        print(item)
' 2>/dev/null || true)

if [[ -n "$ENABLED_BG_MODES" ]]; then
    while IFS= read -r mode; do
        [[ -n "$mode" ]] || continue
        case "$mode" in
            remote-notification)
                if [[ -f "$ENTITLEMENTS" ]] \
                   && /usr/bin/plutil -extract 'aps-environment' raw -o - "$ENTITLEMENTS" >/dev/null 2>&1; then
                    echo -e "  ${GREEN}OK${NC}: UIBackgroundModes=remote-notification ↔ aps-environment present"
                else
                    echo -e "${RED}FAIL${NC}: UIBackgroundModes declares 'remote-notification' but"
                    echo "       aps-environment is missing from $ENTITLEMENTS."
                    echo "       APNs registration will silently fail; silent push will not arrive."
                    echo "       Add: <key>aps-environment</key><string>development</string>"
                    ERRORS=$((ERRORS + 1))
                fi
                ;;
            processing|fetch)
                if plist_has_key BGTaskSchedulerPermittedIdentifiers; then
                    echo -e "  ${GREEN}OK${NC}: UIBackgroundModes=$mode ↔ BGTaskSchedulerPermittedIdentifiers present"
                else
                    echo -e "${RED}FAIL${NC}: UIBackgroundModes declares '$mode' but"
                    echo "       BGTaskSchedulerPermittedIdentifiers is missing from $INFO_PLIST."
                    echo "       BGTaskScheduler.register will throw at launch."
                    ERRORS=$((ERRORS + 1))
                fi
                ;;
            *)
                # Other modes (audio, location, voip, bluetooth-central, etc.)
                # have their own consistency rules; extend this case as the
                # app actually adopts them.
                echo -e "  ${YELLOW}NOTE${NC}: UIBackgroundModes=$mode has no companion-key check yet (extend §5 in $0)."
                ;;
        esac
    done <<< "$ENABLED_BG_MODES"
fi

# ---------- 6. Reverse: API used in source ⇒ NS*UsageDescription required ----
# §1 catches orphan declarations; this catches the inverse: someone added
# LAContext but forgot to update Info.plist. That's the original P0-1 bug.

echo "-> Reverse-checking source API usage against Info.plist declarations..."
while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    key="${row%%|*}"
    pattern="${row#${key}|}"
    if [[ "$(api_used_in_sources "$pattern")" == "1" ]]; then
        if plist_has_key "$key"; then
            echo -e "  ${GREEN}OK${NC}: source uses pattern for $key (declared)"
        else
            echo -e "${RED}FAIL${NC}: source matches pattern for $key but key NOT declared in Info.plist"
            echo "         pattern: $pattern"
            echo "         fix: add <key>$key</key><string>...</string> to $INFO_PLIST"
            echo "              or guard the call site if the API isn't actually exercised."
            ERRORS=$((ERRORS + 1))
        fi
    fi
done <<< "$USAGE_API_TABLE"

# ---------- 7. AppIcon set completeness --------------------------------------
# Two acceptable shapes:
#   (a) Xcode 14+ single-size: Contents.json declares exactly one
#       universal/ios 1024x1024 image, file is a PNG of dimensions
#       1024×1024. Xcode auto-generates derived sizes at build time.
#   (b) Traditional explicit idiom set with all required sizes.
# We only enforce (a)'s file-correctness for now since the project uses
# single-size mode; switching to (b) would require the full size matrix.

if [[ ! -d "$APPICON_SET" ]]; then
    echo -e "${RED}FAIL${NC}: AppIcon.appiconset missing at $APPICON_SET"
    ERRORS=$((ERRORS + 1))
else
    contents_json="$APPICON_SET/Contents.json"
    if [[ ! -f "$contents_json" ]]; then
        echo -e "${RED}FAIL${NC}: $contents_json missing"
        ERRORS=$((ERRORS + 1))
    else
        # Use Python (always present on macOS / CI) for safe JSON parsing
        # — relying on grep against JSON would mis-parse multi-line shapes.
        appicon_status=$(python3 - "$contents_json" "$APPICON_SET" <<'PYEOF'
import json
import os
import struct
import sys

contents_path, set_dir = sys.argv[1], sys.argv[2]

try:
    with open(contents_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, json.JSONDecodeError) as exc:
    print(f"FAIL|Contents.json unreadable: {exc}")
    sys.exit(0)

images = data.get("images", [])
if not images:
    print("FAIL|Contents.json declares no images")
    sys.exit(0)

# Single-size mode requires exactly one universal/ios entry sized 1024x1024
if len(images) == 1:
    img = images[0]
    expected_idiom = img.get("idiom") == "universal"
    expected_platform = img.get("platform") == "ios"
    expected_size = img.get("size") == "1024x1024"
    filename = img.get("filename")
    if not (expected_idiom and expected_platform and expected_size):
        print(
            "FAIL|Single-image AppIcon must be idiom=universal platform=ios "
            f"size=1024x1024 (got idiom={img.get('idiom')} "
            f"platform={img.get('platform')} size={img.get('size')})"
        )
        sys.exit(0)
    if not filename:
        print("FAIL|Contents.json single image entry has no filename")
        sys.exit(0)
    png_path = os.path.join(set_dir, filename)
    if not os.path.isfile(png_path):
        print(f"FAIL|Declared icon file not found on disk: {filename}")
        sys.exit(0)
    # Read PNG IHDR (first 24 bytes) for dimensions
    try:
        with open(png_path, "rb") as fh:
            header = fh.read(24)
        if header[:8] != b"\x89PNG\r\n\x1a\n":
            print(f"FAIL|{filename} is not a PNG")
            sys.exit(0)
        width, height = struct.unpack(">II", header[16:24])
    except (OSError, struct.error) as exc:
        print(f"FAIL|Could not read PNG header for {filename}: {exc}")
        sys.exit(0)
    if (width, height) != (1024, 1024):
        print(
            f"FAIL|{filename} dimensions are {width}x{height}, must be 1024x1024 "
            "for Xcode single-size mode (auto-derives all idioms)"
        )
        sys.exit(0)
    print("OK|Xcode single-size AppIcon (1024x1024 universal/ios) verified")
    sys.exit(0)

# Multi-image mode: at minimum verify every declared filename exists. The
# full Apple size matrix changes per release and is best left to ITMS.
missing = []
for img in images:
    name = img.get("filename")
    if not name:
        continue
    if not os.path.isfile(os.path.join(set_dir, name)):
        missing.append(name)
if missing:
    print("FAIL|Contents.json references missing icon files: " + ", ".join(missing))
else:
    print("OK|Multi-image AppIcon set: all declared files present (Apple size matrix verified at archive)")
PYEOF
        )
        verdict="${appicon_status%%|*}"
        message="${appicon_status#${verdict}|}"
        if [[ "$verdict" == "OK" ]]; then
            echo -e "  ${GREEN}OK${NC}: $message"
        else
            echo -e "${RED}FAIL${NC}: $message"
            ERRORS=$((ERRORS + 1))
        fi
    fi
fi

# ---------- summary ----------------------------------------------------------

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}FAIL: iOS permission gate failed with $ERRORS error(s).${NC}"
    exit 1
fi

echo -e "${GREEN}OK: iOS permission gate passed.${NC}"
exit 0
