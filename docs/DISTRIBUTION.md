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

The tap is **live** at [`harf-promo/homebrew-tap`](https://github.com/harf-promo/homebrew-tap);
the canonical cask is mirrored in this repo at [`Casks/decaffeinate.rb`](../Casks/decaffeinate.rb).

```sh
brew tap harf-promo/tap
brew trust harf-promo/tap        # Homebrew 5+ requires trusting third-party taps once
brew install --cask decaffeinate
```

**Per-release tap mirror (REQUIRED — do not skip):**
1. Bump `version` + `sha256` in **this repo's** `Casks/decaffeinate.rb` (done by CI
   workflow after the sha is known).
2. **Also mirror those same two values** into the separate
   `harf-promo/homebrew-tap` repo's `Casks/decaffeinate.rb` — Homebrew reads
   the _tap_, not this repo. Without this step, `brew upgrade --cask decaffeinate`
   never sees the new release. Use the GitHub UI or API to edit the file directly.
   The `url` line interpolates `#{version}` so it re-resolves automatically — only
   `version` and `sha256` need changing.

> **Note:** `SUFeedURL` uses `/releases/latest/download/` which resolves to the
> latest **non-prerelease, non-draft** GitHub release. Never mark a production
> release tag as prerelease or draft — if you do, `latest` will point at the
> previous release and in-app updates will stop working until you un-mark it.

Submitting to **homebrew/cask core** later removes the `brew trust` step (and
requires the pinned `sha256` + notarized artifact we already produce).

## Auto-update (Sparkle) — shipped

Sparkle 2.x is wired in:
- SPM dependency in `Package.swift`; `Sparkle.framework` is embedded into the
  `.app` by `build-app.sh` (and signed inside-out for Developer ID — verified
  through notarization).
- `UpdaterController` + a "Check for Updates…" item in the menu footer.
- `Info.plist` carries `SUFeedURL`
  (`…/releases/latest/download/appcast.xml`) and `SUPublicEDKey`.
- The **EdDSA private key** is in 1Password (`Sparkle EdDSA Private Key
  (Decaffeinate)`, Harf Promotions vault) and the `SPARKLE_PRIVATE_KEY` repo
  secret. `release.yml` runs `generate_appcast` to publish a signed `appcast.xml`
  on every release. Rotate by re-running `generate_keys` and updating both the
  `SUPublicEDKey` and the secret.

Updates roll out to 1.2.0 and later (the first Sparkle-enabled build).

## Want to own distribution?

If you've shipped a notarized Mac app before, this is one of the highest-impact
places to help — open a
[discussion](https://github.com/harf-promo/decaffeinate/discussions).
