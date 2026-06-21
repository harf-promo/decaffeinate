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

## Near term

- [ ] **Submit to homebrew/cask core** (removes the one-time tap step) — the cask
  is style-ready; gated only on notability. See [`HOMEBREW-CORE.md`](HOMEBREW-CORE.md).

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
