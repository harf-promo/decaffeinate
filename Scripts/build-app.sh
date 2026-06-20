#!/usr/bin/env bash
#
# Builds Decaffeinate.app from the SwiftPM executable.
#
#   ./Scripts/build-app.sh            # release build → ./build/Decaffeinate.app
#   CONFIG=debug ./Scripts/build-app.sh
#
# Signing:
#   - default: ad-hoc signed so it launches locally.
#   - set DEVELOPER_ID="Developer ID Application: Name (TEAMID)" to sign for
#     distribution with the hardened runtime + entitlements (ready to notarize).
# See docs/DISTRIBUTION.md.
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

ENTITLEMENTS="Resources/Decaffeinate.entitlements"
if [[ "${CI:-}" == "true" && "${CONFIG}" == "release" && -z "${DEVELOPER_ID:-}" ]]; then
    echo "✗ Refusing to ad-hoc sign a release build in CI without DEVELOPER_ID" >&2
    exit 1
fi
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    echo "▸ Signing with Developer ID (hardened runtime) …"
    codesign --force --options runtime --timestamp \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${DEVELOPER_ID}" "${APP_BUNDLE}"
    codesign --verify --strict --verbose=2 "${APP_BUNDLE}"
else
    echo "▸ Ad-hoc signing (local use only) …"
    codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 \
        || echo "  (codesign skipped/failed — bundle still runnable locally)"
fi

echo "✓ Built ${APP_BUNDLE}"
echo "  Run with:  open ${APP_BUNDLE}"
echo "  Or CLI:    ${APP_BUNDLE}/Contents/MacOS/${APP_NAME} --scan"
