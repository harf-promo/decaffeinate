# Distribution & Notarization

Decaffeinate must run **outside** the App Store sandbox — it spawns
`/usr/bin/pmset` and reads system-wide power-assertion telemetry, neither of
which is permitted to a sandboxed App Store app. So it is distributed as:

1. **Source** you build yourself, and
2. **A notarized DMG + Homebrew cask** — the pipeline is built and ready; it
   just needs an Apple Developer ID configured as repo secrets (below).

## Building locally (no signing identity)

```sh
./Scripts/build-app.sh        # → build/Decaffeinate.app, ad-hoc signed
./Scripts/make-dmg.sh         # → build/Decaffeinate-<version>.dmg
open build/Decaffeinate.app
```

Ad-hoc signing is enough to run on the machine that built it. Another Mac will
refuse it under Gatekeeper until it's Developer-ID signed and notarized.

## Signing locally with a Developer ID

```sh
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" ./Scripts/build-app.sh
./Scripts/make-dmg.sh
xcrun notarytool submit build/Decaffeinate-*.dmg \
  --key AuthKey.p8 --key-id <KEY_ID> --issuer <ISSUER_ID> --wait
xcrun stapler staple build/Decaffeinate-*.dmg
```

The entitlements live in `Resources/Decaffeinate.entitlements` (non-sandboxed;
the hardened runtime needs no extra entitlement to spawn `pmset`).

## Automated releases (recommended)

`.github/workflows/release.yml` runs the whole chain on a `v*` tag push:
**build → Developer-ID sign → DMG → `notarytool submit --wait` → staple →
upload to the GitHub Release** (plus `SHA256SUMS.txt`). It also stamps the
version into `Info.plist` from the tag.

### One-time setup — add these repository secrets

Settings → Secrets and variables → Actions:

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | base64 of your exported "Developer ID Application" `.p12` |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password |
| `DEVELOPER_ID_NAME` | `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_KEY_P8` | base64 of your App Store Connect API key (`.p8`) |
| `NOTARY_KEY_ID` | the API key id |
| `NOTARY_ISSUER_ID` | the API key issuer id |

```sh
# Export the cert from Keychain Access as cert.p12, then:
base64 -i cert.p12 | pbcopy            # → DEVELOPER_ID_CERT_P12
base64 -i AuthKey_XXXX.p8 | pbcopy     # → NOTARY_KEY_P8
```

Then cut a release: `git tag v1.1.0 && git push origin v1.1.0`.

> ⚠️ Apple's notarization service had intermittent multi-day delays in early
> 2026 — check the [system status](https://developer.apple.com/system-status/)
> if `notarytool` hangs in "In Progress".

## Homebrew cask

A ready cask lives at [`Casks/decaffeinate.rb`](../Casks/decaffeinate.rb). To
offer `brew install --cask`:

1. Create a tap repo named `harf-promo/homebrew-tap`.
2. Copy `Casks/decaffeinate.rb` into its `Casks/` directory.
3. Users then run:
   ```sh
   brew tap harf-promo/tap
   brew install --cask decaffeinate
   ```

It uses `sha256 :no_check` so it tracks new releases without per-release edits.
Submitting to **homebrew/cask core** later requires a pinned `sha256` (printed by
`make-dmg.sh` and published as `SHA256SUMS.txt` on each release) and a notarized
artifact.

## Auto-update (next)

Sparkle 2.x is the planned updater (works with SwiftPM once wrapped as a `.app`):
add the SPM dependency, an `SPUStandardUpdaterController` + "Check for Updates…"
menu item, an EdDSA key (public key in `Info.plist`), and an `appcast.xml`
generated and signed in `release.yml`. Tracked as a follow-up.

## Want to own distribution?

If you've shipped a notarized Mac app before, this is one of the highest-impact
places to help — open a
[discussion](https://github.com/harf-promo/decaffeinate/discussions).
