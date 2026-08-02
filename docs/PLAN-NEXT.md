# Decaffeinate — Next Milestones (v1.21 → v1.25)

*Product-audit plan, 2026-07-19. Basis: a 6-agent discovery run — full product-surface inventory, a 35-finding heuristic UX review, a competitive teardown of Juicy (getjuicy.app), lid-closed technical research (Apple docs + adrafinil / Amphetamine / Fermata / Sleepless source), and two synthesis designs. Owner decision recorded: **lid-closed ships tiered — zero-root Clamshell Assistant for everyone + opt-in privileged helper.** This document is planning only; each milestone is executed (and verified with `swift build && swift test`) separately.*

## The three headline findings

1. **The released product is 7 versions behind the code.** Last tag, `Info.plist`, and the Homebrew cask are all **1.13.0**; the code is at **1.20.0** (CHANGELOG marks 1.14–1.20 "Unreleased"). Users cannot install the Harf redesign, wake-reasons, stale-CPU evidence, agent hooks, or the MCP server. README/ROADMAP describe unreleased work as shipped. **Nothing on this plan matters more than closing this gap.**
2. **Juicy is a battery-management app, not a keep-awake app** ($14.99–$24.99, macOS 15+, 4.85★ MAS, Apple-featured twice). Its lid-closed ability is one line on a charge-limiting page with an undisclosed mechanism. What's worth stealing is its **experience discipline**: pill/glow alert presentation, a stated fire-once anti-nag rule, 7d/30d history sparklines, themeable glanceable menu-bar icon, and its SEO compare-page growth engine. What's worth **inverting** is its opacity: publish exactly how lid-closed works (and why it needs root) as a transparency page.
3. **True lid-closed-without-a-display requires root — confirmed again.** `kIOPMAssertionAppliesOnLidClose` is entitlement-gated (killed Fermata); adrafinil field-verified all private in-process routes fail; Amphetamine's sandboxed claim is fragile on Apple Silicon. Zero-root buys exactly one thing: Apple's built-in clamshell mode (external display + AC + external input). Hence the tiered design in v1.24.

## UX review — the P1 debt (full 35-finding list in the Appendix)

- **Force-sleep is a surprise.** Idle force-sleep fires with no on-screen warning, no cancel; the confirming notification and menu-bar countdown are both opt-out-by-default. The highest-trust moment is the weakest UX.
- **Notifications: on-by-default drip, not actionable, silently dies if denied.** No batching, no quiet hours, no action buttons ("open the app to decide"), no repair path after a denial.
- **No at-a-glance status.** The 4 menu-bar icon states are near-identical at 16px; the countdown is opt-in; you must open the popover to know anything.
- **The popover is a dense dashboard**, ALL-CAPS 11px status line, no row-expand affordance, no many-holders strategy, fixed font sizes (no Dynamic Type).
- **Onboarding: 4 marketing panels, no launch-at-login offer (default OFF — the app dies at next restart), Skip still fires the OS notification prompt.**
- **Localization is a stub that over-promises**: `de.lproj` exists but ~95% of UI is hardcoded English.
- **Sleep Now bypasses the app's own call guard** — pressed during a Zoom call it sleeps mid-call, contradicting "never cuts off calls."

---

## Milestones

Codename convention continues (Solid, Sharp, Deep, Connected, Evidence, Integrated, Global → …).

### v1.21 — **Public** · *ship what exists*

Pure debt-clearing; no features. Everything later rides on a live release channel.

| # | Item | Size | Where |
|---|------|------|-------|
| 1 | Configure signing/notarization secrets, tag v1.20 (or v1.21 rollup), release the notarized DMG; Sparkle updates flow | S (owner + tag) | `.github/workflows/release.yml`, repo secrets |
| 2 | Doc-drift sweep: README/ROADMAP/AUTOMATION stop describing unreleased work as shipped; fix hard-coded `"version": "1.17.0"` example | S | `README.md`, `docs/*.md` |
| 3 | Cask bump automation: release CI updates cask version+sha256 in both repo and tap so distribution can't lag again | M | `release.yml`, `Casks/decaffeinate.rb`, tap repo |
| 4 | `--help` completeness: `--status`, `--sleep-if-idle`, `--install-hook`, `--uninstall-hook`, `--mcp` all listed; dev flags stay hidden by stated policy | S | `Core/CLI.swift` |
| 5 | homebrew/cask core submission attempt (notability-gated; retry after v1.25 compare pages if declined) | S | `docs/HOMEBREW-CORE.md` |

### v1.22 — **Calm** · *every interruption earns its place; a forced sleep is never a surprise*

All fixes, sequenced before anything new touches `Notifier`, `AppState`, or `OnboardingView`.

| # | Item | Size | Where |
|---|------|------|-------|
| 1 | **Pre-sleep countdown HUD, on by default** — "Sleeping in 20 s — Stay awake" pill with cancel, Juicy-grade presentation; no more abrupt `pmset sleepnow` | M | new `Views/SleepWarningHUD.swift`, `AppState.tick()/forceSleep`, `AppSettings` |
| 2 | **Sleep Now call guard** — every entry point (button, hotkey, intent, URL, CLI) confirms when a mic/screen-share hold is active | S | `AppState.sleepNow`, `MenuRedesign.RDActionBar` |
| 3 | Name the culprit on failed sleep: "…— **Docker** is holding system sleep open" | S | `AppState.reconcilePendingSleepFeedback` |
| 4 | **Actionable notifications** — "Always allow" / "Sleep anyway" buttons on new-blocker alerts (`UNNotificationCategory` + delegate); keep the fixed privacy-safe copy | M | `Core/Notifier.swift`, firewall queue |
| 5 | **Burst digest + fire-once anti-nag rule** — coalesce "3 apps started keeping your Mac awake"; one alert per state change per holder; adopt as a stated, documented principle (Juicy's discipline) | M | `Notifier`, `AppState.updateFirewallQueue` |
| 6 | **Notification-permission repair path** — detect denial; in-menu nudge + Settings status row deep-linking to System Settings; the firewall can no longer go silently dead | M | `Notifier`, `MenuRedesign`, `SettingsView` |
| 7 | **Onboarding rework** — collapse 4 panels → 2; explicit "Enable notifications" vs "Not now"; Skip defers the OS prompt to the first real blocker; add the trust line ("no screen recording, no accessibility access, everything stays on your Mac") | M | `Views/OnboardingView.swift` |
| 8 | **Launch-at-login offered in onboarding** (or default ON) — the one setting that lets a background utility survive a restart | S | `AppSettings`, `OnboardingView`, `Core/LoginItem.swift` |
| 9 | Sleep-simulation test harness so HUD/guard/digest paths are deterministic under `swift test` | M | `Tests/`, seams in `AppState`/`SleepController`/`Notifier` |

### v1.23 — **Glanceable** · *"will my Mac sleep?" readable in one second*

Fixes land first — they restructure the exact files the new items extend.

| # | Item | Size | Where |
|---|------|------|-------|
| 1 | **Icon state differentiation at 16px** + a distinct "blocked" treatment on by default (at-a-glance status without the countdown) | M | `MugIcon.swift`, `BrandMark.swift`, `DecaffeinateApp.swift` |
| 2 | One metaphor everywhere — Shortcuts stops saying "cup and saucer / Caffeinate my Mac" while the app says moon | S | `AppIntents.swift`, `MugState` |
| 3 | **Menu density restructure** — top third protected for the verdict; restart hint + screen-only section behind a disclosure; sentence-case readable status line replaces the ALL-CAPS 11px eyebrow; "More…" → "Keep awake…" | L | `MenuRedesign.swift` |
| 4 | Row affordances + scale — persistent disclosure chevron; duplicates/agent sessions collapse with "show N more" | M | `MenuRedesign.RDRow/RDList`, `HoldGroup.swift` |
| 5 | **Dynamic Type in the menu** — replace fixed `.system(size:)` throughout; popover grows | M | `MenuRedesign.swift`, `Components.swift` |
| 6 | Settings IA split + guardrails — Notifications/Startup out of the 8-section General wall; plain-language glosses ("Battery floor — the charge level where keep-awake gives up"); warn below ~3-min idle threshold; strict takeover visually marked Advanced | M | `SettingsView.swift` |
| 7 | Optional holder count / themed treatment in the menu-bar icon (Juicy's most-requested area) | S | `DecaffeinateApp.swift`, `BrandMark` |
| 8 | Keep-awake hotkeys (Sleep Now deliberately stays unbound by default) | S | `DecaffeinateApp.swift`, `SettingsView` |
| 9 | "Works with Shortcuts & Siri" discoverability line — the 4 existing intents stop being a secret | S | `SettingsView` (About), onboarding |
| 10 | **Weekly awake-time history** — "which app held your Mac awake longest this week," 7d/30d sparklines on existing history + stale-CPU stores (Juicy proves history views sell) | M | `SleepHistoryStore.swift`, `StaleHolderDetector.swift`, History pane |
| 11 | Control Center control + widget spike → ship — backed by existing App Intents. **Risk:** needs an app-extension bundle the manual `build-app.sh` pipeline doesn't produce; time-box a feasibility spike first | L | new extension target, `Scripts/build-app.sh` |

### v1.24 — **Closed** · *the lid-closed answer — owner-approved tiered design*

Positioned after Glanceable deliberately: the largest trust-boundary change in the app's history should ride on a repaired trust surface. Consider tagging **2.0** if Tier 2 ships. Docs change **before** code (honest-copy ethos): ARCHITECTURE.md non-goal splits into still-true negative knowledge + the new optional-helper section; README's no-root table row updates; new `docs/LID-CLOSED.md` transparency page ships **even if Tier 2 aborts** (the Juicy-inversion play: differentiation via transparency).

**Phase A — Clamshell Assistant (zero-root, M):**
- New sensing components mirroring existing reader patterns: `LidStateReader` (`AppleClamshellState` via IOPMrootDomain + `kIOPMMessageClamshellStateChange` notification; ~20-year-stable constants; degrades to "unknown" behind a protocol seam), `DisplayTopologyReader` (`CGGetOnlineDisplayList`/`CGDisplayIsBuiltin`), best-effort external-input probe, `SleepDisabledReader` (parse `SleepDisabled` from `pmset -g` on menu-open + ~30 s cadence — never in the hot tick).
- Pure decision engine `ClamshellAdvisor.classify(lid, displays, power, inputs) → .notApplicable / .ready / .missing({power, externalDisplay, externalInput})` — fully unit-testable.
- Menu → "Keep awake…" → **"Use with lid closed…"**: live readiness checklist; when ready, "Arm clamshell session" flips the existing keep-awake and says "close the lid — your Mac keeps working on the external display." Fallback when no display: "keep working with the screens off" (keep-awake + existing `displaysleepnow`, copy states the lid must stay open). Wake-on-network hint from the `womp` flag (link to System Settings; never pretend to set it).
- Lid-aware `SleepOutlook` phrasing; foreign-`SleepDisabled` warning banner ("Sleep is disabled system-wide — set outside Decaffeinate") — observability no competitor has.
- Surface: `--clamshell-status [--json]`, `clamshell_status` MCP tool, `ClamshellStatusIntent`. **Deliberately no MCP/Shortcuts/URL toggle for Tier 2** — an AI agent must never flip a root-backed global flag.

**Phase B — optional Lid-Closed Helper (privileged, opt-in, L, gated):**
- Timeboxed **spike first (~1 week, build-flag, no release)** with explicit ABORT criteria: (a) SMAppService daemon registration + approval works on the non-Xcode `build-app.sh` bundle; (b) `disablesleep 1` empirically holds a closed displayless Apple Silicon MacBook awake on current macOS; (c) reboot behavior of the flag confirmed; (d) notarization of the embedded helper passes; (e) cheap re-check of Amphetamine's claimed public API (evidence says fragile dead end). Any failure → ship Tier 1 + transparency page only.
- If green: new SwiftPM target `DecaffeinateLidHelper`, mechanism-only XPC surface (`acquireLease(ttl)/renewLease/releaseLease/currentState/helperVersion` — nothing else); helper hard-codes: clear flag on launch (reboot antidote), on SIGTERM, on lease expiry (~30 s heartbeats from the app, dead-man grace ~3 min), TTL hard cap 8 h. App-side `LidHelperClient` behind a `LidClosedControlling` seam + `LidClosedSession` pure state machine.
- Trust story, all four legs: opt-in install with a blocking full-disclosure sheet (mechanism named incl. "undocumented, system-wide, root-only"; risks unsoftened — heat/bag/battery; rails enumerated; exact on-disk footprint + removal); visible state (fifth `MugState.lidClosedHold` with a genuinely distinct silhouette, "LID-CLOSED · 42 M LEFT" status, banner); one-command removal (`--uninstall-lid-helper` + Settings button + cask `uninstall` stanza); auto-revert watchdog **in the helper**, not the app.
- Safety rails extend `SafetyRails.evaluate` (not forked): AC-required by default; opt-in battery use floors at hard-min 25%; thermal ladder stricter than keep-awake (`.fair` warn → `.serious` end lease → `.critical` Backpack Guard, releasing the lease **before** `sleepnow` — sequencing matters, the kernel flag defeats sleepnow); lid-open >60 s auto-release; max-duration only, no indefinite mode.
- New settings: `clamshellAssistEnabled` (default true), `lidClosedRequiresAC` (true), `lidClosedMaxMinutes` (120), `lidClosedBatteryFloorPercent` (25); helper install state never persisted — reconciled live from `SMAppService.status` (the `LoginItem` pattern).
- Tests: readiness matrix, `pmset -g` fixture parsing, rails extensions, lease state machine, reconcile state machine, fakes for all new seams — all `swift test`. Manual QA checklist for real clamshell hardware, approval flow, `kill -9` revert, reboot-clears-flag, zero-residue uninstall.

**Dependencies:** Public shipped (no trust-boundary change on a stale channel) · Calm shipped (reuses confirm-dialog, anti-nag, and permission-repair-row patterns) · existing rails (battery floor, thermalState, Backpack Guard) reused as clamshell rails.

### v1.25 — **Fluent** · *speak the user's language; speak up for the project*

Deliberately last — Calm/Glanceable rewrite most user-facing strings; extracting earlier means localizing twice.

| # | Item | Size | Where |
|---|------|------|-------|
| 1 | Route shipping surfaces through L10n — menu, Settings, `SleepOutlook` verdicts, `ReasonEngine`, `Notifier`, CLI; the `de.lproj` promise becomes true | L | `Core/Localization.swift`, `*.lproj`, all Views |
| 2 | Community language expansion (2–3 languages; documented good-first-PR path; Juicy's MAS reviews show demand e.g. Chinese) | M | `docs/LOCALIZATION.md`, `Info.plist` |
| 3 | Compare pages + press kit (vs Amphetamine, KeepingYouAwake, Coffee, Juicy) — the zero-budget growth channel Juicy proved; feeds the cask-core notability case | M | docs/site only, no app code |

---

## Kill-list (deliberately excluded, with reasons)

- **Battery health / charge limiting / Sailing Mode / Power Flow wattage** (Juicy's core) — identity dilution; Decaffeinate is a sleep firewall, and Juicy proves that category is already taken.
- **SMC temperature/fan sensors** — reverse-engineered maintenance risk; `ProcessInfo.thermalState` covers the rail (research-confirmed).
- **Animated sleep-blocker flow diagram** — high polish cost; the `SleepOutlook` verdict already answers what the viz would decorate.
- **Red pulsing screen glow** — contradicts the calm ethos; the pre-sleep HUD spends the attention budget on the one moment that earns it.
- **Per-alert custom sounds / lifecycle (created/released/expired) alerts** — contradicts the fire-once anti-nag principle; marginal value.
- **iPhone/iPad/Bluetooth device battery features** — identity dilution + scanning maintenance tail.
- **Private-API/MAS-style clamshell hacks** — field-verified broken on Apple Silicon, entitlement-gated; dead end.
- **Scoped-sudoers clamshell path** (Sleepless pattern) — a passwordless-root grant outlives the app; the approvable, revocable SMAppService helper is the ceiling.
- **App Store distribution** — Juicy's own feature-cut MAS build demonstrates the sandbox cost; reaffirmed non-goal.
- **Default Sleep-Now hotkey binding** — an unbound-by-default destructive action is correct.

## Appendix — full 35-finding UX review index

P1: 4-panel onboarding before value · no launch-at-login offer/default-off · icon states illegible at 16px · no default at-a-glance status · popover cognitive load · no Dynamic Type in menu · General pane 8-section wall · notification drip (no batching/quiet hours) · notifications not actionable · denial kills firewall silently · **idle force-sleep with no warning/cancel** ·
P2: Skip fires OS prompt · notif panel implies absent choice · split moon/cup metaphor · "More…" hides keep-awake · no row-expand affordance · no many-holder scaling · ALL-CAPS micro status line · jargon in power corners · 1-min idle slider unguarded · strict takeover unmarked · Sleep Now bypasses call guard · failed-sleep names no culprit · localization stub over-promises · restart content demotable · no widget/Control Center · hotkey covers one action unbound ·
P3 (good/keep): destructive confirms consistent · privacy-safe notification copy · honest sleep mechanism · copy tone a strength · Shortcuts coverage strong (surface it) · trust-win line missing in onboarding · optional state-change sound.
