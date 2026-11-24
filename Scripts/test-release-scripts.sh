#!/usr/bin/env bash
#
# Tests for the release shell helpers (Scripts/version.sh, Scripts/bump-cask.sh).
# Runs without secrets or network: `./Scripts/test-release-scripts.sh`.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/version.sh
source "$here/version.sh"

failures=0
fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

expect_build() {
    local got
    got="$(bundle_version_from_marketing "$1")" || { fail "$1 → error"; return; }
    [ "$got" = "$2" ] || fail "bundle_version_from_marketing $1 → $got, want $2"
}

expect_build 1.10.1 1010001
expect_build v2.3.7 2003007
expect_build 1.26.2 1026002
# Leading zeros are base 10, not octal (bash rejects 08 as octal).
expect_build 1.08.09 1008009

for good in 1.2.3 v1.2.3 v10.999.999 1.08.0; do
    validate_release_version "$good" || fail "validate_release_version rejected $good"
done
for bad in 1.2.3-beta1 v1.2.3-rc.1 1.2.3.4 1.2 v1 "" 1.1000.0 1.2.1000 x1.2.3 "1.2.3 "; do
    if validate_release_version "$bad"; then
        fail "validate_release_version accepted '$bad'"
    fi
done

# bump-cask.sh: rewrites version + sha256, and fails when the cask's shape
# no longer matches (instead of reporting "already at" with nothing changed).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/release-tests.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
sha="$(printf 'a%.0s' {1..64})"

cat > "$tmp/ok.rb" <<'RUBY'
cask "decaffeinate" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
RUBY
"$here/bump-cask.sh" "$tmp/ok.rb" 1.2.3 "$sha" || fail "bump-cask.sh failed on a well-formed cask"
grep -qx '  version "1.2.3"' "$tmp/ok.rb" || fail "bump-cask.sh did not set the version"
grep -qx "  sha256 \"$sha\"" "$tmp/ok.rb" || fail "bump-cask.sh did not set the sha256"

cat > "$tmp/shape.rb" <<'RUBY'
cask "decaffeinate" do
  version '1.0.0'
  sha256 arm: "0000000000000000000000000000000000000000000000000000000000000000"
end
RUBY
if "$here/bump-cask.sh" "$tmp/shape.rb" 1.2.3 "$sha" 2>/dev/null; then
    fail "bump-cask.sh accepted a cask whose version/sha256 lines it could not edit"
fi

# The real cask must stay editable, so a reshaped cask fails CI, not a release.
cp "$here/../Casks/decaffeinate.rb" "$tmp/real.rb"
"$here/bump-cask.sh" "$tmp/real.rb" 9.8.7 "$sha" || fail "bump-cask.sh cannot edit Casks/decaffeinate.rb"

if "$here/bump-cask.sh" "$tmp/ok.rb" 1.2.3 "not-a-sha" 2>/dev/null; then
    fail "bump-cask.sh accepted a malformed sha256"
fi

if [ "$failures" -ne 0 ]; then
    echo "$failures failure(s)" >&2
    exit 1
fi
echo "release script tests: all passed"
