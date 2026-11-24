#!/usr/bin/env bash
#
# Set a cask's `version` and `sha256`, then check both landed.
#
# Usage: Scripts/bump-cask.sh <cask.rb> <version> <sha256>
#
# Used by release.yml for both the Homebrew tap and this repo's canonical copy.
# If the cask's lines change shape, sed matches nothing; without the check below
# the workflow would then print "already at <version>" and ship a stale cask.
set -euo pipefail

cask="${1:?usage: bump-cask.sh <cask.rb> <version> <sha256>}"
version="${2:?usage: bump-cask.sh <cask.rb> <version> <sha256>}"
sha="${3:?usage: bump-cask.sh <cask.rb> <version> <sha256>}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "bump-cask.sh: '$version' is not MAJOR.MINOR.PATCH" >&2
    exit 1
}
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || {
    echo "bump-cask.sh: '$sha' is not a sha256 hex digest" >&2
    exit 1
}

# -i.bak works with both BSD and GNU sed.
sed -i.bak \
    -e "s/^\( *\)version \"[^\"]*\"/\1version \"$version\"/" \
    -e "s/^\( *\)sha256 \"[^\"]*\"/\1sha256 \"$sha\"/" \
    "$cask"
rm -f "$cask.bak"

if ! grep -Eq "^ *version \"$version\"\$" "$cask" || ! grep -Eq "^ *sha256 \"$sha\"\$" "$cask"; then
    echo "bump-cask.sh: $cask has no plain 'version \"…\"' / 'sha256 \"…\"' line to update — fix the cask or this script." >&2
    exit 1
fi
