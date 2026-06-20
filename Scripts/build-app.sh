#!/usr/bin/env bash
#
# Builds Decaffeinate.app from the SwiftPM executable.
#
#   ./Scripts/build-app.sh            # release build → ./build/Decaffeinate.app
#   CONFIG=debug ./Scripts/build-app.sh
#
# The resulting bundle is ad-hoc signed so it launches locally. For public
# distribution you still need to sign with a Developer ID and notarize it
# (see docs/DISTRIBUTION.md).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP_NAME="Decaffeinate"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "▸ Building (${CONFIG}) …"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "✗ Executable not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "▸ Assembling ${APP_BUNDLE} …"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

if [[ -f "assets/AppIcon.icns" ]]; then
    cp "assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
else
    echo "  (no assets/AppIcon.icns — run: swift Scripts/generate-icon.swift)"
fi

# Ad-hoc sign so Gatekeeper lets it run locally.
echo "▸ Ad-hoc signing …"
codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || \
    echo "  (codesign skipped/failed — bundle still runnable locally)"

echo "✓ Built ${APP_BUNDLE}"
echo "  Run with:  open ${APP_BUNDLE}"
echo "  Or CLI:    ${APP_BUNDLE}/Contents/MacOS/${APP_NAME} --scan"
