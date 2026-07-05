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

# Copy SwiftPM resource bundles (e.g. KeyboardShortcuts' localized .strings) so
# each package's Bundle.module accessor resolves at runtime. Without this,
# KeyboardShortcuts.RecorderCocoa.init fatalErrors ("unable to find bundle named
# KeyboardShortcuts_KeyboardShortcuts") the moment the Settings window renders the
# hotkey recorder. The accessor searches Bundle.main.resourceURL first — i.e.
# Contents/Resources/ — so that's where the bundle must land.
for _bundle in "${BIN_DIR}"/*.bundle; do
    [[ -e "${_bundle}" ]] || continue
    echo "▸ Bundling resource: $(basename "${_bundle}")"
    cp -R "${_bundle}" "${APP_BUNDLE}/Contents/Resources/"
done
# Guard: KeyboardShortcuts is a required dep whose recorder needs its bundle —
# fail loudly if it didn't make it in, rather than shipping a Settings crash.
if grep -q "KeyboardShortcuts" Package.swift \
    && [[ ! -d "${APP_BUNDLE}/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle" ]]; then
    echo "✗ KeyboardShortcuts resource bundle missing — Settings would crash (Bundle.module)" >&2
    exit 1
fi

# Embed Sparkle.framework (the executable links @rpath/Sparkle.framework and has
# an @executable_path/../Frameworks rpath). BIN_DIR was resolved above.
FRAMEWORK="${BIN_DIR}/Sparkle.framework"
if [[ -d "${FRAMEWORK}" ]]; then
    echo "▸ Embedding Sparkle.framework …"
    mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
    cp -R "${FRAMEWORK}" "${APP_BUNDLE}/Contents/Frameworks/"
fi

# Extract App Intents metadata so Shortcuts / Spotlight / Siri can discover the
# intents. SwiftPM's Swift Build backend emits per-module `.swiftconstvalues`
# during the build above; `appintentsmetadataprocessor` turns those into the
# `Metadata.appintents` bundle (SwiftPM's `swift build` does NOT run it — only
# Xcode does). Must run BEFORE codesign so the bundle is inside the seal. Fully
# guarded: any missing piece degrades to the `decaffeinate://` URL scheme + CLI,
# which always work — so a toolchain change can never fail the release build.
APPINTENTS_PROC="$(xcrun --find appintentsmetadataprocessor 2>/dev/null || true)"
APPINTENTS_CONST="$(find .build -path "*${APP_NAME}.build*" \
    -name "${APP_NAME}-primary.swiftconstvalues" 2>/dev/null | head -1)"
if [[ -n "${APPINTENTS_PROC}" && -x "${APPINTENTS_PROC}" && -n "${APPINTENTS_CONST}" ]]; then
    echo "▸ Extracting App Intents metadata …"
    _AI_SRCS="${BUILD_DIR}/appintents-sources.txt"
    _AI_CONST="${BUILD_DIR}/appintents-constvals.txt"
    _AI_XCODE="$(xcodebuild -version 2>/dev/null | awk '/Build version/{print $NF}')"
    find "Sources/${APP_NAME}" -name '*.swift' >"${_AI_SRCS}"
    printf '%s\n' "${APPINTENTS_CONST}" >"${_AI_CONST}"
    if "${APPINTENTS_PROC}" \
        --output "${APP_BUNDLE}/Contents/Resources" \
        --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
        --module-name "${APP_NAME}" \
        --sdk-root "$(xcrun --show-sdk-path)" \
        --xcode-version "${_AI_XCODE:-1}" \
        --platform-family macOS \
        --deployment-target 14.0 \
        --target-triple "arm64-apple-macos14.0" \
        --source-file-list "${_AI_SRCS}" \
        --swift-const-vals-list "${_AI_CONST}"; then
        echo "  ✓ Metadata.appintents written (Shortcuts/Spotlight/Siri discovery)"
    else
        echo "  (App Intents metadata step failed — Shortcuts still works via the URL scheme)"
    fi
    rm -f "${_AI_SRCS}" "${_AI_CONST}"
else
    echo "  (No App Intents const-values found — Shortcuts discovery falls back to the URL scheme)"
fi

ENTITLEMENTS="Resources/Decaffeinate.entitlements"
SPARKLE="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    echo "▸ Signing with Developer ID (hardened runtime) …"
    if [[ -d "${SPARKLE}" ]]; then
        # Sign Sparkle inside-out (notarization requires every nested binary signed).
        # Resolve the current framework version dir dynamically — do NOT hardcode
        # "Versions/B": a Sparkle framework-version-letter bump would otherwise make
        # this loop silently sign nothing and fail notarization downstream.
        if [[ -L "${SPARKLE}/Versions/Current" ]]; then
            V="${SPARKLE}/Versions/$(readlink "${SPARKLE}/Versions/Current")"
        else
            V=""
            for cand in "${SPARKLE}"/Versions/[A-Z]; do
                [[ -d "${cand}" ]] && V="${cand}"
            done
        fi
        if [[ -z "${V}" || ! -d "${V}" ]]; then
            echo "✗ Could not resolve Sparkle framework version dir under ${SPARKLE}/Versions" >&2
            exit 1
        fi
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
