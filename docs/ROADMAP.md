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

## Near term

- [ ] **Submit to homebrew/cask core** (removes the one-time `brew trust`).
- [ ] **Universal binary** — currently Apple Silicon only; add an `x86_64` slice.
- [ ] 🙋 **Onboarding** — a first-run explainer of what the app does and why it's safe.

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
