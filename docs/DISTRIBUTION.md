# Distribution & Notarization

Decaffeinate must run **outside** the App Store sandbox — it spawns
`/usr/bin/pmset` and reads system-wide power-assertion telemetry, neither of
which is permitted to a sandboxed App Store app. So it is distributed as:

1. **Source** you build yourself (works today), and
2. **A notarized DMG / Homebrew cask** (on the [roadmap](ROADMAP.md)).

This document is the working notes for (2). Help wanted!

## Building locally (no signing identity)

```sh
./Scripts/build-app.sh        # → build/Decaffeinate.app, ad-hoc signed
open build/Decaffeinate.app
```

Ad-hoc signing (`codesign --sign -`) is enough to run on the machine that built
it. Another Mac will refuse it under Gatekeeper until it's Developer-ID signed
and notarized.

## Releasing a notarized build (target workflow)

Requires an Apple Developer account and a "Developer ID Application" certificate.

```sh
# 1. Build
CONFIG=release ./Scripts/build-app.sh

# 2. Sign with Developer ID + hardened runtime
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <Your Name> (<TEAMID>)" \
  build/Decaffeinate.app

# 3. Package into a DMG (e.g. with create-dmg)
create-dmg build/Decaffeinate.app build/

# 4. Notarize
xcrun notarytool submit build/Decaffeinate-1.0.0.dmg \
  --apple-id "<you@example.com>" --team-id "<TEAMID>" \
  --password "<app-specific-password>" --wait

# 5. Staple the ticket
xcrun stapler staple build/Decaffeinate-1.0.0.dmg
```

## Entitlements

The hardened runtime needs an entitlement to spawn `pmset`. A starting
`Decaffeinate.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
</dict>
</plist>
```

(No sandbox; default hardened-runtime allowances are sufficient for shelling out
to `pmset`. Refine as we test on clean machines.)

## Homebrew cask (target)

Once notarized DMGs are attached to GitHub Releases, a cask is straightforward:

```ruby
cask "decaffeinate" do
  version "1.0.0"
  sha256 "..."
  url "https://github.com/harf-promo/decaffeinate/releases/download/v#{version}/Decaffeinate-#{version}.dmg"
  name "Decaffeinate"
  desc "The truth about what keeps your Mac awake — and the power to make it sleep"
  homepage "https://github.com/harf-promo/decaffeinate"
  app "Decaffeinate.app"
end
```

## Want to own distribution?

This is one of the highest-impact areas for a contributor. If you have an Apple
Developer account and have shipped a notarized Mac app before, please reach out
via a [discussion](https://github.com/harf-promo/decaffeinate/discussions) — we'd
love the help.
