#!/usr/bin/env bash
#
# Packages build/Decaffeinate.app into a compressed, drag-to-install DMG.
# Run after ./Scripts/build-app.sh. For a distributable build, sign first with
# DEVELOPER_ID=... ./Scripts/build-app.sh, then notarize the DMG (see
# docs/DISTRIBUTION.md).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Decaffeinate"
APP_BUNDLE="build/${APP_NAME}.app"

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "✗ ${APP_BUNDLE} not found — run ./Scripts/build-app.sh first" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
    "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || echo "1.0.0")"
DMG="build/${APP_NAME}-${VERSION}.dmg"

echo "▸ Building ${DMG} …"
rm -f "${DMG}"
STAGING="$(mktemp -d)"
cp -R "${APP_BUNDLE}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING}" \
    -ov -format UDZO \
    "${DMG}" >/dev/null

rm -rf "${STAGING}"

echo "✓ ${DMG}"
shasum -a 256 "${DMG}"
