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

# Release builds are universal (Intel + Apple Silicon); debug stays host-arch for
# fast local iteration. Override with UNIVERSAL=1 / UNIVERSAL=0.
UNIVERSAL="${UNIVERSAL:-$([[ "${CONFIG}" == "release" ]] && echo 1 || echo 0)}"
ARCH_FLAGS=()
if [[ "${UNIVERSAL}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
    echo "▸ Building (${CONFIG}, universal arm64+x86_64) …"
else
    echo "▸ Building (${CONFIG}) …"
fi
# `${arr[@]+"${arr[@]}"}` expands safely even for an empty array under `set -u`
# on macOS's bash 3.2.
swift build -c "${CONFIG}" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

BIN_DIR="$(swift build -c "${CONFIG}" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
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

# Stamp a deterministic CFBundleVersion derived from the marketing version
# (so locally-built and CI-built apps both report the correct, consistent build
# number — never the placeholder "1" from the source Info.plist).
# shellcheck source=Scripts/version.sh
source "$(dirname "$0")/version.sh"
_MV="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
    "${APP_BUNDLE}/Contents/Info.plist")"
_BV="$(bundle_version_from_marketing "$_MV")"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $_BV" \
    "${APP_BUNDLE}/Contents/Info.plist"
unset _MV _BV

if [[ -f "assets/AppIcon.icns" ]]; then
    cp "assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
else
    echo "  (no assets/AppIcon.icns — run: swift Scripts/generate-icon.swift)"
fi

# Embed Sparkle.framework (the executable links @rpath/Sparkle.framework and has
# an @executable_path/../Frameworks rpath). BIN_DIR was resolved above.
FRAMEWORK="${BIN_DIR}/Sparkle.framework"
if [[ -d "${FRAMEWORK}" ]]; then
    echo "▸ Embedding Sparkle.framework …"
    mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
    cp -R "${FRAMEWORK}" "${APP_BUNDLE}/Contents/Frameworks/"
fi

ENTITLEMENTS="Resources/Decaffeinate.entitlements"
SPARKLE="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    echo "▸ Signing with Developer ID (hardened runtime) …"
    if [[ -d "${SPARKLE}" ]]; then
        # Sign Sparkle inside-out (notarization requires every nested binary signed).
        V="${SPARKLE}/Versions/B"
        for item in \
            "${V}/XPCServices/Downloader.xpc" \
            "${V}/XPCServices/Installer.xpc" \
            "${V}/Updater.app" \
            "${V}/Autoupdate" \
            "${V}/Updater.app/Contents/MacOS/Updater"; do
            [[ -e "${item}" ]] && codesign --force --options runtime --timestamp \
                --sign "${DEVELOPER_ID}" "${item}"
        done
        codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID}" "${SPARKLE}"
    fi
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
