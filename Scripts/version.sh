#!/usr/bin/env bash
#
# Shared helper: derive a deterministic, monotonic CFBundleVersion from a
# marketing version string.
#
# Usage:
#   source Scripts/version.sh
#   bundle_version_from_marketing "1.10.1"   # → 1010001
#   bundle_version_from_marketing "2.3.7"    # → 2003007
#
# Formula: major*1_000_000 + minor*1_000 + patch
#   Safe as long as minor < 1000 and patch < 1000 — comfortably beyond any
#   realistic semver. The wider radix prevents the minor-≥100 collision that
#   the old 10000/100 formula had (e.g. 1.100.0 == 2.0.0 there).
#   This replaces the GITHUB_RUN_NUMBER coupling (which could produce a lower
#   build number if a workflow re-ran for an older tag), making update eligibility
#   a pure function of the marketing version.
#
# Worked examples — verify monotonicity across the historical versions:
#   1.9.0   → 1009000   (formerly stamped as build 13)
#   1.10.0  → 1010000   (1010000 > 13, so all 1.9.0/build-13 users get the update)
#   1.10.1  → 1010001   (1010001 > 1010000 ✓)
#   2.0.0   → 2000000
#
# Releases are plain MAJOR.MINOR.PATCH only (validate_release_version). A
# pre-release tag would become the `latest` release — the Sparkle feed and the
# cask — and "1.2.3-beta1" would get the same CFBundleVersion as "1.2.3", so
# Sparkle would never move beta users to the final build. Components are read
# in base 10, so "1.08.0" is 1008000, not an octal error.

# Succeeds only for vMAJOR.MINOR.PATCH / MAJOR.MINOR.PATCH with minor and patch
# below 1000 (the formula's radix).
validate_release_version() {
    local v="${1#v}"
    # Digit bounds keep 10#… arithmetic far from overflow and the build
    # number at most 999_999_999.
    [[ "$v" =~ ^[0-9]{1,3}\.[0-9]{1,4}\.[0-9]{1,4}$ ]] || return 1
    local major minor patch
    IFS='.' read -r major minor patch <<< "$v"
    (( 10#$minor < 1000 && 10#$patch < 1000 ))
}

bundle_version_from_marketing() {
    local v="${1:?bundle_version_from_marketing requires a version argument}"
    # Strip any leading 'v'
    v="${v#v}"
    # Split on '.' — we only need the first three components.
    local major minor patch_raw patch
    IFS='.' read -r major minor patch_raw <<< "$v"
    # Strip any trailing non-digits from patch; callers validate first.
    patch="${patch_raw%%[^0-9]*}"
    # Base-10 arithmetic; empty/missing components default to 0.
    echo $(( 10#${major:-0} * 1000000 + 10#${minor:-0} * 1000 + 10#${patch:-0} ))
}
