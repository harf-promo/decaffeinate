#!/usr/bin/env bash
#
# Shared helper: derive a deterministic, monotonic CFBundleVersion from a
# marketing version string.
#
# Usage:
#   source Scripts/version.sh
#   bundle_version_from_marketing "1.10.0"   # → 11000
#   bundle_version_from_marketing "2.3.7"    # → 20307
#
# Formula: major*10000 + minor*100 + patch
#   Safe as long as minor < 100 and patch < 100.
#   This replaces the GITHUB_RUN_NUMBER coupling (which could produce a lower
#   build number if a workflow re-ran for an older tag), making update eligibility
#   a pure function of the marketing version.
#
# Worked examples:
#   1.9.0  → 10900   (the last released build, formerly stamped as 13)
#   1.10.0 → 11000   (11000 > 13, so Sparkle offers the update to all 1.9.0 users)
#   2.0.0  → 20000
#
# Pre-release suffixes on patch (e.g. "1.10.0-beta1") are stripped before
# arithmetic so they don't cause parse errors.

bundle_version_from_marketing() {
    local v="${1:?bundle_version_from_marketing requires a version argument}"
    # Strip any leading 'v'
    v="${v#v}"
    # Split on '.' — we only need the first three components.
    local major minor patch_raw patch
    IFS='.' read -r major minor patch_raw <<< "$v"
    # Strip a pre-release suffix from patch (e.g. "0-beta1" → "0").
    patch="${patch_raw%%[^0-9]*}"
    # Arithmetic (bash integer context; empty/missing components default to 0).
    echo $(( ${major:-0} * 10000 + ${minor:-0} * 100 + ${patch:-0} ))
}
