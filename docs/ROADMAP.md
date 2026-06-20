# Roadmap

Decaffeinate v1 does one thing well: it tells you what's keeping your Mac awake
and puts it to sleep when it should. Here's where we want to take it — and where
**you** can jump in. Items tagged 🙋 are especially good for new contributors.

## Done (1.1.0)

- [x] **Agentic completion detection** — watch a process tree's CPU + assertion
  lifecycle and sleep once the work finishes.
- [x] **Assertion attribution** — shared-daemon holds traced to the real app.
- [x] **Notarized DMG + Homebrew pipeline** — signing, `make-dmg`, tag-triggered
  `release.yml`, and a cask (publishing a signed build needs the maintainer's
  Developer-ID secrets — see `docs/DISTRIBUTION.md`).
- [x] **Custom allow durations** + an injectable, integration-tested decision loop.

## Near term

- [ ] **Auto-update** — Sparkle 2.x (EdDSA appcast generated in `release.yml`).
- [ ] **Submit to homebrew/cask core** (needs pinned `sha256` + a public release).
- [ ] 🙋 **README screenshots** of the menu, list, and settings.
- [ ] 🙋 **Onboarding** — a first-run explainer of what the app does and why it's safe.
- [ ] 🙋 **Richer menu-bar icons** — true "empty / filling / warning" mug states as a
  custom icon set instead of SF Symbols.

## Smarter sleep

- [ ] **Schedules** — per-app and per-time-of-day rules (e.g. never force sleep
  during work hours; always sleep after midnight).
- [ ] **Quiet windows** — temporary "stay awake until X" without a permanent rule.
- [ ] **Triggers / automation** — stay awake while app X runs / on AC / above a
  CPU threshold (the main feature gap vs Amphetamine).

## Deeper system insight

- [ ] **SMC sensors** — real temperature and fan reads for a smarter Backpack
  Guard, beyond `ProcessInfo.thermalState`. *(Reverse-engineered only — weigh the
  maintenance cost.)*
- [ ] ~~Camera / mic in-use detection~~ — no public API exists; not pursuing.

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
