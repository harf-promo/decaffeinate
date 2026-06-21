# Changelog

All notable changes to Decaffeinate are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] — 2026-06-21

The "why", not just the "what" — Decaffeinate now explains *why* each app is
holding your Mac awake, and finishes the v1 roadmap.

### Added
- **Reason engine** — every sleep blocker now carries a plain-English reason and
  an icon, read from public IOKit assertion keys: **microphone in use** (honest
  `audio-in` detection — "likely a call"), **playing media / audio**, **software
  update**, **Time Machine backup**, **Handoff/Continuity**, **keeps display on**,
  and **auto-releases in N s** for timed assertions. The real owner behind shared
  daemons (`coreaudiod`, `runningboardd`) is attributed where macOS exposes it.
- **Per-blocker detail** — tap any row to expand the full picture: reason,
  resource chips (Microphone/Speaker), real owner, how long it's been held,
  auto-release countdown, assertion type, and bundle path. `--scan` prints it too.
- **First-run onboarding** (#7) — a three-panel welcome (what it does · the safety
  promise · the one notification permission), replayable from About.
- **Sleep history & insights** (#9) — a rolling log of forced sleeps with the
  reason and a rough "needless wake avoided" estimate (Settings → History).
- **Schedules** (#8) — "active hours" during which Decaffeinate never *forces*
  sleep, so long tasks and your own work are never cut off (Settings → Schedule).
- **Quiet windows** (#8) — a one-shot "Stay awake until…" from the menu (30 m / 1 h
  / 2 h / until 6 PM) that holds the Mac awake, then auto-releases.
- **Menu-bar countdown** (#10) — optionally show the live "M:SS" to sleep beside
  the menu-bar icon.

### Changed
- Smarter headline that folds the dominant blocker's reason in ("Safari is playing
  media", "Your microphone is in use").
- The media safety rail now also honours `audio-in`/`audio-out` resource signals.

## [1.3.0] — 2026-06-20

### Added
- **Universal binary** — Intel **and** Apple Silicon (was arm64-only).
- **Sleep sooner on battery** — a shorter idle threshold when unplugged (default 3 min).
- The menu always shows the core promise ("Sleeps ~N min after you step away")
  when no live countdown is up.

### Changed
- UX polish from a multi-agent review: keep-awake now visibly pauses auto-sleep;
  clearer firewall labels ("Let it sleep" / "Not now") with a primary Allow; the
  watcher is retitled "Sleep when a task finishes" with grouped candidates and an
  always-visible explainer; assertion rows surface attribution + how long they've
  been held instead of the PID.
- Visuals: the status card escalates to red on overheating / low battery, a
  distinct keep-awake hue, and dark-mode-aware tints; better section-header contrast.
- Accessibility labels on all icon-only controls.
- Honest precision: the only network call is the optional Sparkle update check.

### Removed
- Dead code and duplicated view logic (shared subtitle + allow-duration menu).

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
