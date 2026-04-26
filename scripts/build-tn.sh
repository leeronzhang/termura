#!/bin/bash
# Build the `tn` CLI tool and copy it into the app bundle.
# Called as an Xcode pre-build script phase.
set -euo pipefail

BIN_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Resources/bin"

# Skip in CI or when explicitly disabled.
if [ "${SKIP_TN_BUILD:-0}" = "1" ]; then
    echo "note: Skipping tn build (SKIP_TN_BUILD=1)"
    exit 0
fi

# Build tn CLI via SPM (release for smaller binary).
swift build \
    -c release \
    --package-path "${PROJECT_DIR}" \
    --product tn \
    --scratch-path "${PROJECT_DIR}/.build" \
    2>&1 | tail -5

# Copy binary into app bundle.
mkdir -p "$BIN_DIR"
cp "${PROJECT_DIR}/.build/release/tn" "$BIN_DIR/tn"
chmod +x "$BIN_DIR/tn"

echo "note: tn CLI installed to $BIN_DIR/tn"
