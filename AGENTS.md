# Decaffeinate — agent contract

macOS menu-bar app (SwiftPM executable, macOS 14+) — a *sleep firewall*: it shows exactly what's holding the Mac awake (IOKit power assertions via `IOPMCopyAssertionsByProcess`) and forces an idle Mac to sleep with `pmset sleepnow`. Keep-awake is a secondary, opt-in mode — it does **not** wrap `caffeinate`. Public repo `harf-promo/decaffeinate`: unlimited Actions minutes, direct push to `main` is allowed (PR optional).

## Layout

- `Package.swift` — SwiftPM manifest; executable target `Decaffeinate`, tests in `Tests/DecaffeinateTests`
- `Sources/` — app code · `Resources/`, `assets/` — icons etc.
- `Scripts/` — release tooling: `version.sh` (derives CFBundleVersion: major×1_000_000 + minor×1_000 + patch), `build-app.sh` (app bundle), `make-dmg.sh`, `generate-icon.sh`
- `Casks/decaffeinate.rb` — Homebrew cask; update on release

## Commands (verified)

```bash
swift build            # debug build (~10 s warm)
swift test             # XCTest suite — 256 tests across 20 files in Tests/DecaffeinateTests
swift build -c release
```

## Release flow

1. Bump the marketing version (see `Scripts/version.sh` header for the CFBundleVersion formula — do NOT reintroduce GITHUB_RUN_NUMBER coupling).
2. `Scripts/build-app.sh` → `Scripts/make-dmg.sh`.
3. Update `Casks/decaffeinate.rb` (version + sha256).

## Verification before done

`swift build && swift test`; for UI/menu-bar behavior, run the built app and observe — menu-bar interactions are not machine-checkable, name what to click when handing over.
