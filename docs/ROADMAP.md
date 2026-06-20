# Roadmap

Decaffeinate v1 does one thing well: it tells you what's keeping your Mac awake
and puts it to sleep when it should. Here's where we want to take it — and where
**you** can jump in. Items tagged 🙋 are especially good for new contributors.

## Near term

- [ ] **Notarized DMG + Homebrew cask** — Developer-ID signing, notarization, and
  a one-line `brew install --cask decaffeinate`. *(DevOps / release engineering.)*
- [ ] **Auto-update** — Sparkle or a GitHub-Releases-based updater.
- [ ] 🙋 **Onboarding** — a first-run explainer of what the app does and why it's safe.
- [ ] 🙋 **Richer menu-bar icons** — true "empty / filling / warning" mug states as a
  custom icon set instead of SF Symbols.

## Smarter sleep

- [ ] **Agentic completion detection** — "sleep when the build / agent finishes,"
  by watching a chosen process tree's CPU and assertion lifecycle rather than a
  fixed idle timer.
- [ ] **Schedules** — per-app and per-time-of-day rules (e.g. never force sleep
  during work hours; always sleep after midnight).
- [ ] **Quiet windows** — temporary "stay awake until X" without a permanent rule.

## Deeper system insight

- [ ] **Assertion attribution** — trace holds routed through shared daemons
  (`coreaudiod`, `runningboardd`) back to the real owner (the browser tab, the
  music app). The data is in the assertion name; this is a great IOKit puzzle.
- [ ] **SMC sensors** — real temperature and fan reads for a smarter Backpack
  Guard, beyond `ProcessInfo.thermalState`.
- [ ] **Camera / mic in-use** detection for better call awareness.

## Insight & polish

- [ ] **Sleep history** — a timeline of forced sleeps and what triggered them.
- [ ] **Battery saved** estimate — show the impact over time.
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
