# Changelog

All notable changes to Decaffeinate are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.2] — 2026-06-21

Hardening and delivery — from an adversarial review of the 1.5.1 menu.

### Added
- **"Update available" button** in the footer, raised the moment Sparkle's
  background check finds a new version — updates can't be missed. (The cask stays
  `auto_updates true`; the README now documents `brew upgrade --cask decaffeinate
  --greedy` for a forced Homebrew update.)

### Fixed
- **The popover can never clip again** — the height is now screen-aware
  (`min(460, screen·0.8)`), so the pinned footer (Settings/quit) stays on screen
  on small displays; the body scrolls within whatever fits. Width 380 for the
  richer rows.
- **Approval buttons can't vanish** — a sibling hold from the same app (same
  firewall key, different assertion id) is now correctly recognised as pending,
  so its Allow/Block buttons render.
- **No menu stall** — app icons resolve after first paint (off the synchronous
  render path), with a bounded cache; the category symbol shows until ready.
- **All active modes are cancelable** — a quiet window *and* a watch (etc.) now
  each show their own cancel line, instead of only the first.
- Menu-bar `free` crescent reads better at 18px; approval buttons carry explicit
  VoiceOver labels; tidied a brittle layout constant.

## [1.5.1] — 2026-06-21

A menu UX overhaul and a new unified mark.

### Fixed
- **Settings is reachable again.** The popover had no height cap or scroll, so a
  tall stack got clipped and the footer (Settings/quit) went off-screen. Rebuilt
  as three zones — a pinned header, one scrolling body, and a pinned footer (fixed
  360×460) — so Settings is always on screen and the blocker list has real room.

### Changed
- **New "nightcap" mark, everywhere.** Replaced the crescent/sun set with a single
  ownable mark — a flat coffee cup with one green crescent moon rising like steam.
  Used consistently across the app icon (cup + crescent on an ink "night" field),
  the menu-bar family (empty + crescent → draining → full & steaming → bolt; no
  sun), onboarding, About, and the README.
- **Fewer buttons, more meaning.** One hero "Sleep Now" + a single "Keep awake"
  menu (keep awake · stay awake until… · auto-sleep · sleep-when-a-task-finishes)
  replace the old toggle pair, quiet-window control, and watch block; a single
  cancelable line shows the active mode.
- **Context to approve.** The firewall is merged into the list — an item needing a
  decision shows inline Allow / Allow for… / Let it sleep, highlighted. Every row
  now carries the **real app icon**, the plain reason, **who's behind it** ("via
  coreaudiod" / the real app), and held-for / auto-release. Tap → a readable,
  copyable detail (Why · Held by · Real app · Routed via · Where on disk · …).

## [1.5.0] — 2026-06-21

A visual redesign in the **Harf design system**, a **new logo**, and the
triggers/automation feature.

### Added
- **New logo** — a flat geometric crescent moon + a single green accent dot
  (sleep, the honest inverse of a coffee cup), replacing the brown-gradient mug.
  The menu-bar icon becomes a moon ↔ sun family (crescent · crescent+star · sun ·
  bolt). Authored as a vector SVG (`assets/decaffeinate-mark.svg`).
- **Triggers / automation** — keep the Mac awake *while* a condition holds: an app
  is running, on AC power, or CPU is busy (Settings → Triggers). The safety rails
  (battery floor / backpack guard) still override.

### Changed
- **Adopted the Harf design system** across the app: a SwiftUI token layer
  (brand grey + green, ink/paper scales, the positive/warning/critical/info status
  family, the √2 spacing ladder, the 5/4 type scale, sharp corners, hairlines).
- **Onboarding redesigned** editorially — a quiet masthead, UPPERCASE-tracked step
  eyebrows, a heavy display heading, a grey lede, green-dot bullets, numeral step
  indicators, and an ink primary "Get started →" button.
- **Menu, status card and Settings** re-skinned: the moon mark's *shape* carries
  the state with a thin status-coloured rule (no full-card wash — clean in dark
  mode); ink primary "Sleep Now"; hairlines, stamped pills, eyebrow section heads;
  green kept as punctuation, with teal for active state.

### Other
- The Homebrew cask is now `brew style`-clean and cask-core-ready (see
  `docs/HOMEBREW-CORE.md`). 138 tests.

## [1.4.1] — 2026-06-21

A correctness, safety, privacy & accessibility pass from a 37-finding adversarial
audit of 1.4.0. No new features — everything here makes the existing ones more
trustworthy.

### Fixed — sleep correctness & safety
- **No more "neither sleeps nor stays awake" limbo.** A quiet window under the
  battery floor (or thermal pressure) now stops holding and lets force-sleep
  re-engage; the active-hours schedule yields to the battery floor too.
- **Stale media can't pin the Mac awake forever.** Audio-out / display-on holds
  release after you've been idle past the threshold + 30 min (a forgotten
  background tab). The microphone/call guard is now its own setting and is never
  idle-capped.
- **Anti-spoofing.** Time Machine / software-update detection trusts the verified
  owning process (backupd / softwareupdated / installd), not a caller-controlled
  assertion *name* — closing a trivial force-sleep bypass.
- The overheating / critical-battery backpack guard has its own cooldown, so an
  unrelated idle sleep can't muzzle it.
- `pmset sleepnow` no longer blocks the main actor (the menu could hang at the
  moment of sleep).

### Fixed — honesty in the UI
- The menu no longer says "Free to sleep" / "Sleeps ~N min" while it's actually
  holding sleep off — it shows "Auto-sleep paused — <reason>".
- Quiet-window rows say "paused — <reason>" when a safety rail drops the hold,
  instead of claiming "Awake until X".
- The watcher shows "finished — sleep paused" when a schedule/quiet window is
  holding. Schedule settings gain a live "Active now / next window" indicator.

### Fixed — privacy
- Notifications show a classified reason ("Playing media"), never the raw,
  app-controlled assertion name (which can leak a media title to the lock screen).
- App-supplied reason text and the `--scan` output are sanitized (control/ANSI
  stripped, clamped).

### Fixed — accessibility
- VoiceOver announces the menu-bar countdown; assertion rows are real buttons with
  expand state; sliders/pickers get labels & values; the badge font scales;
  onboarding panels scroll at large Dynamic Type.

### Changed
- The `.ignore` rule reads "Ignored" / "Let it sleep" consistently (was "Blocked").
- 127 tests (was 100); removed dead code; rule expiry uses the injected clock.

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
