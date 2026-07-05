# Roadmap

Decaffeinate v1 does one thing well: it tells you what's keeping your Mac awake
and puts it to sleep when it should. Here's where we want to take it — and where
**you** can jump in. Items tagged 🙋 are especially good for new contributors.

## Shipped

**1.1.0** — agentic completion detection; assertion attribution; custom allow
durations; an injectable, integration-tested decision loop; and the full
**signed + notarized DMG → GitHub Release → Homebrew** pipeline.

**1.2.0** — **Sparkle auto-update** (EdDSA-signed appcast, generated in
`release.yml`); **custom menu-bar mug icons**; README screenshots.

**1.3.0** — **universal binary** (Intel + Apple Silicon); "sleep sooner on
battery"; a UX/visual/copy polish pass and dead-code cleanup.

**1.4.0** — the **reason engine**: *why* each app keeps the Mac awake (incl.
honest **microphone-in-use** detection via the public `audio-in` resource key),
with per-blocker detail; **onboarding**; **sleep history**; **schedules** &
**quiet windows**; and an optional **menu-bar countdown**.

**1.4.1** — a 37-finding adversarial audit: safety-rail correctness, UX honesty,
privacy and accessibility hardening.

**1.5.0** — adopts the **Harf design system** (new crescent logo, a SwiftUI token
layer, redesigned onboarding/menu/settings); **triggers / automation**
(keep-awake while an app runs / on AC / CPU busy).

**1.6.0** — a ground-up **Nightcap** redesign driven by real rendered screenshots:
the menu and a native five-pane Settings sidebar rebuilt, shape-distinct menu-bar
icon states, and a live-SwiftUI screenshot harness; retired the old `ImageRenderer`
preview path and dead helpers.

**1.7.0 / 1.7.1** — **process provenance** (trace each hold back to the window /
terminal / agent / project via public `libproc`/`sysctl`) and **agentic awareness**
(parse the `caffeinate` command line, recognise AI-agent sessions, offer "Sleep when
it finishes", auto-sleep toggle, `--provenance` CLI); churning agent-`caffeinate`
respawns coalesce into one stable per-session row; upgrades no longer reset settings.

**1.8.0** — clearer holds: per-hold **lifetime** (until done / timed / indefinite),
a header "won't sleep until…" line, **audio-source device naming** (CoreAudio), a
stably alphabetical list, and row actions (bring to front / Activity Monitor / copy).

**1.9.0** — the **Rest & Restart** pillar: an uptime hero and a calm restart
recommendation escalating toward the ~49.7-day networking cliff, a display-off / sleep
/ restart explainer, a rest timeline, and a "recommend after N days" setting.

**1.10.0 / 1.10.1** — **in-app updates fixed** (deterministic `CFBundleVersion`) with
visible update-status UI; three opt-out notifications; a configurable CPU-trigger
threshold; accessibility labels — then a council-verified honesty/correctness pass:
truly-measured sleep metric, persisted restart-overdue de-dup, urgency escalation,
notification-auth gating, an updater no longer stuck on "Checking…", a widened
`version.sh` formula, and a `release.yml` appcast-upload guard.

**1.11.0** — **radically simplified menu**: every hold leads with a plain ✓/⚠ verdict,
an aggregate verdict banner, a consolidated action area, and plain-language "Always
allow" / "Sleep anyway" / "Allow for…" with a single source of truth for policy verbs.

## Near term

- [ ] **Submit to homebrew/cask core** (removes the one-time tap step) — the cask
  is style-ready; gated only on notability. See [`HOMEBREW-CORE.md`](HOMEBREW-CORE.md).
- [ ] **App Intents / Shortcuts & URL-scheme automation** — Sleep Now, "What's
  keeping my Mac awake", Keep Awake for…, and Stop as Shortcuts / Siri / Spotlight
  actions, plus a `decaffeinate://` URL scheme, `--sleep-now` / `--keep-awake` CLI,
  and a global Sleep-Now hotkey. *(In progress.)*

## Deeper system insight

- [ ] **SMC sensors** — real temperature and fan reads for a smarter Backpack
  Guard, beyond `ProcessInfo.thermalState`. *(Reverse-engineered only — weigh the
  maintenance cost.)*
- [x] **Microphone-in-use detection** — shipped in 1.4.0 via the public
  `ResourcesUsed`/`audio-in` assertion key (no private API needed). Camera has no
  equivalent public signal; not pursuing.

## Insight & polish

- [x] **Sleep history** — shipped in 1.4.0 (Settings → History), with a rough
  "needless wake avoided" estimate.
- [ ] 🙋 **Localization** — translations beyond English.
- [ ] 🙋 **More tests** — a sleep-simulation harness; broader coverage.

## Non-goals (for now)

- Keeping a Mac awake with the lid closed / on battery with no display — that's
  [Sleepless](https://github.com/Aboudjem/Sleepless)' job and needs `pmset
  disablesleep` (root). Decaffeinate stays root-free.
- App Store distribution — incompatible with spawning `pmset` and reading
  system-wide telemetry.

---

Want to own one of these? Open a [discussion](https://github.com/harf-promo/decaffeinate/discussions)
or comment on the matching issue. See [`CONTRIBUTING.md`](../CONTRIBUTING.md) to get started.
