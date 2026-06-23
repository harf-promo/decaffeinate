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
# Pre-release suffixes on patch (e.g. "1.10.1-beta1") are stripped before
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
    echo $(( ${major:-0} * 1000000 + ${minor:-0} * 1000 + ${patch:-0} ))
}
