# Changelog

All notable changes to Decaffeinate are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — 2026-06-20

### Added
- **Auto-update** via Sparkle 2.x — a "Check for Updates…" item in the menu, and
  each release publishes an EdDSA-signed `appcast.xml` so the app keeps itself
  current. (Updates roll to 1.2.0+; the bundle is Apple Silicon.)
- **Custom menu-bar mug icons** — empty / half-full / steaming / bolt, replacing
  the SF Symbols, drawn at runtime as template images.
- **README screenshots** rendered deterministically via a hidden
  `--render-previews` mode (no flaky popover capture).

## [1.1.0] — 2026-06-20

The "make it real" release: distribution (signed + notarized DMG, Homebrew),
the flagship agentic feature, deeper truth, and a tested decision loop.

### Added
- **Agentic completion detection** — watch a build/agent (by process name or PID)
  and let the Mac sleep once its subtree goes quiet and releases its assertions.
  New `ProcessWatcher` (libproc CPU sampling) + `AgentWatcher` + a "Sleep when
  finished" menu section.
- **Assertion attribution** — holds routed through `coreaudiod` / `runningboardd`
  are traced to the real app (e.g. "Safari (via runningboardd)") in the list and
  `--scan`.
- **Distribution pipeline** — `Resources/Decaffeinate.entitlements`, Developer-ID
  signing in `build-app.sh`, `make-dmg.sh`, a tag-triggered
  `release.yml` (sign → notarize → staple → publish), and a Homebrew cask.
- **Custom allow durations** — Allow for 30 min / 1 hour / 4 hours / until tomorrow.

### Changed
- `AppState`'s engines are now injectable behind protocols; the `tick()` decision
  loop has full integration tests (66 tests total).
- `swift-format` + `.editorconfig` added; CI now lints strictly.

### Fixed
- A lapsed "allow for 1 hour" now re-prompts instead of staying silently blocked.
- Immediate (thermal/battery) sleep guards honor the cooldown — no per-second
  `pmset` spawn storm or sleep/wake thrash.
- A failed `pmset` no longer reports a phantom "Slept"; the idle threshold is
  clamped so a `0` can't force constant sleep; `IdleMonitor` no longer force-unwraps.

## [1.0.0] — 2026-06-20

The first release. Decaffeinate's mission: tell you the truth about what keeps
your Mac awake, and make it sleep when it should.

### Added
- **Truth Scanner** — live, per-process view of every power assertion holding
  the Mac awake, via `IOPMCopyAssertionsByProcess`.
- **Decaffeinate Engine** — forces a safe `pmset sleepnow` after a configurable
  idle threshold, overriding stale keep-awake assertions.
- **Sleep Firewall** — per-app Allow / Allow-for-1-hour / Block rules, with
  prompts when a new app starts holding the Mac awake.
- **Safety Rails** — pause for active media/calls, Time Machine backups, and
  macOS updates; Backpack Guard (sleep on overheating); Battery Floor (drop
  keep-awake holds on low battery).
- **Keep-Awake mode** (optional) — standard system/display assertions, with the
  same safety rails.
- **Menu-bar app** — dynamic icon (free / counting down / blocked / awake),
  status card, live assertion list, settings, and a one-click **Sleep Now**.
- **Headless CLI** — `Decaffeinate --scan` / `--version` / `--help`.
- **Launch at login** via `SMAppService`.
- App icon, ad-hoc app-bundle build script, and unit test suite (28 tests).

[1.0.0]: https://github.com/harf-promo/decaffeinate/releases/tag/v1.0.0
