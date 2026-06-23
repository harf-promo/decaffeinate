# Changelog

All notable changes to Decaffeinate are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — UX simplification: answer-first menu

Radically simplifies the menu so it answers one question per hold: "Will my Mac
sleep on its own, or is something holding it awake indefinitely?" Removes firewall
jargon; reduces top-of-menu clutter; ensures menu and Settings speak the same language.

### Changed
- **Each hold row now leads with a plain verdict.** Below the app name every row
  shows either ✓ "Will sleep when the build finishes" / "Will sleep shortly after
  your agent finishes" / "Auto-releases on a timer" — or ⚠ "Won't sleep on its own
  — held until you act". This is derived from the existing `HoldLifetime` data the
  app already computed; it was previously buried as a tiny trailing badge.
- **Aggregate verdict banner.** Above the hold rows a single teal/amber line
  summarises the whole picture: "Your Mac will sleep on its own when these finish"
  or "Something is holding your Mac awake indefinitely". Any indefinite hold turns
  the banner amber.
- **Top action area simplified.** The menu's action area is now: one primary
  "Sleep Now" button · one "More…" menu (holds "Keep awake" durations and
  "Sleep when done" watch targets) · one "Auto-sleep when idle" on/off toggle.
  The previous four competing controls ("Keep awake" split-menu, embedded "When done"
  watcher menu, auto-sleep toggle, Sleep Now) have been consolidated.
- **"Allow"/"Block" renamed to plain language everywhere.** The pending-row buttons
  that were "Allow" / "Let it sleep" are now **"Always allow"** / **"Sleep anyway"**
  / **"Allow for…"**. The overflow menu and the per-row status tag use the same words.
  Settings now shows "App sleep permissions" (was "Allowed / blocked apps") with a
  one-line caption explaining what each rule does.
- **Single source of truth for policy verbs.** `RulePolicy` now exposes
  `menuActionLabel` (imperative: "Always allow" / "Sleep anyway" / "Allow for…")
  alongside the updated `shortLabel` (settled state: "Allowed" / "Sleeping anyway" /
  "Allowed · timed"). Both the menu tag and the Settings pill draw from these
  properties so they can never read different words for the same rule.
- **Explainer card reworded** to describe the ✓/⚠ glyphs rather than "tap any row
  to see technical details".

### Internal
- `HoldLifetime.rowVerdict` — new pure property; 5 new tests covering all cases
  including the agent re-arming case ("Will sleep shortly after your agent finishes").
- `AppState.sleepVerdict` — new aggregate property; 4 new tests (empty / all-bounded
  / any-indefinite / mixed).
- 256 tests, 0 failures; `swift format lint --strict` clean.

## [1.10.1] — 2026-06-23

Council-verified hardening: honesty, correctness, accessibility, and pipeline
reliability — all grounded in code-level evidence, none speculative.

### Fixed
- **Measured sleep metric is now truly measured.** The history headline "≈ X min
  of measured sleep" previously included a hard-coded 15-min estimate per sleep
  whose wake was never observed — quietly violating the app's honesty promise.
  The headline now shows only genuinely measured minutes (real sleep→wake pairs);
  a secondary line "N sleeps not yet measured" appears when there are unobserved
  events, so no data is hidden. Wake-pairing clamp tightened from 24 h to 4 h so
  a user's overnight manual sleep can no longer be mis-attributed to Decaffeinate.
- **Restart-overdue notification no longer re-nags on every relaunch.** The
  last-notified advice band was in-memory only, so a quit-and-relaunch while still
  in the "consider" band could re-fire the "overdue" notification the user already
  saw. The state is now persisted to `UserDefaults` keyed by the current boot time,
  so it survives relaunches and auto-resets after a real restart.
- **Restart urgency escalation now fires.** `.overdue` and `.urgent` were treated
  as one band, so the more serious `.urgent` threshold (approaching the ~50-day
  networking cliff) never produced a notification. It now re-fires when crossing
  `.overdue → .urgent`.
- **Notifications can no longer fire before authorization.** `post()` was calling
  `requestAuthorizationIfNeeded()` inline, which could surface the OS permission
  sheet cold on first run — defeating the onboarding deferral. `post()` now only
  submits when `authorized == true`; the prompt still arrives via the onboarding
  flow with context.
- **Forced-sleep toggle label now matches behavior.** "Notify me when *I* force
  the Mac to sleep" implied the manual Sleep Now button, but the notification fires
  for all Decaffeinate-triggered sleeps (idle, agent-finished, etc.). Reworded to
  "Notify me when Decaffeinate puts the Mac to sleep."
- **Updater status can no longer get stuck on "Checking…"** If a check cycle
  ended without Sparkle emitting a find/not-found callback (throttled, aborted, or
  dismissed), the UI stayed in the checking state indefinitely. Now resolved to
  `.upToDate` when the cycle ends cleanly without a categorized result.
- **Update failure reason is now visible to all users.** The "Couldn't check"
  reason was previously only reachable via a hover tooltip — invisible to
  VoiceOver and keyboard users. The reason is now also rendered as visible body
  text, and the pill carries an `.accessibilityLabel` that folds it in.
- **`version.sh` widened to prevent minor-≥100 collision.** The old
  `major×10000 + minor×100 + patch` formula collides at `minor ≥ 100`
  (e.g. `1.100.0 == 2.0.0`). Widened to `major×1_000_000 + minor×1_000 + patch`,
  safe to minor/patch < 1000. Verified monotonic: `1.10.1 → 1010001 > 1010000
  (1.10.0) > 11000 (installed)`.
- **`release.yml` now fails on a real appcast upload error.** The trailing `|| true`
  masked genuine `gh release upload` failures, meaning a release could ship without
  an appcast and break every in-app updater silently. Replaced with a clean
  conditional that only tolerates file-absent; real errors surface and fail the job.
  Added an assertion that `generate_appcast` exists before it's invoked.

### Changed
- **"Not checked yet"** replaces a stale "Last checked: … ago" in Settings → About
  when no check has run this session.
- **Relative timestamps now show days and weeks** ("5d ago", "2wk ago") instead of
  capping at hours ("120h ago") — improving readability in the About update row.
- **CPU trigger slider explains itself.** A caption under the slider describes what
  the threshold does and that the battery floor / backpack guard still override it.
  The "Add" button is disabled (and the caption changes) when a CPU trigger already
  exists, preventing accidental duplicates.

### Internal
- `SleepHistoryStore.unmeasuredSleepCount` added alongside the cleaned-up
  `measuredMinutesAsleep`. Wake-pairing `maxGap` lowered to 4 h.
- `AppState.updateLastNotifiedRestartAdvice(_:)` + `loadPersistedRestartNotificationState()`
  persist the notification de-dup state to UserDefaults keyed by boot time.
- `UpdaterController.didFinishUpdateCycleFor` resolves stuck `.checking` state.
- `Notifier.post()` no longer auto-requests authorization; only `authorized == true`
  lets notifications through.
- 18 new tests in previous release; 247 total passing.

## [1.10.0] — 2026-06-23

Smarter, more honest, more communicative — and the in-app updater now actually
works.

### Fixed
- **In-app updates work again.** `CFBundleVersion` was stamped from
  `${GITHUB_RUN_NUMBER}` (a CI counter that happened to be `13`), so Sparkle
  considered every release "up to date" once the user had build 13 installed.
  The build number is now derived deterministically from the marketing version —
  `major×10000 + minor×100 + patch` — so `1.10.0 → 11000` which is
  unambiguously newer than the installed `13`. Future versions can never drift
  again because the formula is the single source of truth (`Scripts/version.sh`).
- **In-app update status shows what's happening.** The Settings → About section
  previously went silent after "Check for Updates…" — there was no feedback on
  whether the check succeeded, failed, or found something. A status row now shows
  one of: *Up to date · checked just now* (green pill), *Checking…* (info pill,
  button disabled), *Update available — Install* (warning pill), or *Couldn't
  check · Try Again* with the reason in a tooltip (critical pill).

### Added
- **Three opt-out notifications** — off by default unless you've clearly opted
  into the relevant feature, honest about what the app actually did:
  - *Forced-sleep confirmation* — fires when the kernel confirms the transition
    (not when pmset is launched), guarded by `notifyOnForcedSleep` (default
    off).
  - *Agent/build finished* — fires at the moment the sleep happens, one-shot
    so it can't re-fire after the watcher clears. On by default because you
    opted into the watch.
  - *Restart overdue* — fires once per crossing into the overdue/urgent band
    (never at launch even if the Mac is already overdue), re-arms after a real
    restart. Off by default.
  Settings → Notifications & startup has a toggle for each.
- **Onboarding panel "More than sleep"** — a new step 03 surfaces the
  keep-awake, agent-watch, and restart-nudge features that new users miss. The
  panel count, step numerals, and page transitions adapt automatically.
- **Configurable CPU trigger threshold** — the "While CPU is busy" trigger no
  longer hard-codes 50%. A slider (10–90%, step 5) lets you add a trigger at any
  threshold. No model change — the existing `cpuAbove(Int)` condition always
  stored the value; only the UI was rigid.
- **Accessibility** — primary menu-bar toggle now has `.accessibilityLabel` +
  `.accessibilityHint`; the two icon-only trash buttons in Settings carry
  `.accessibilityLabel` so VoiceOver users can identify them without activating.

### Changed
- **"Minutes of avoided waking" → "minutes of measured sleep"** — the old
  `events.count × 15` counterfactual (which claimed to know how long the Mac
  *would* have stayed awake) is replaced by the actual measured time from each
  forced sleep to the next observed wake, with a 15-minute fallback only for
  events where the app was quit before the wake fired. The label is now
  "≈ X min of measured sleep started by Decaffeinate."

### Internal
- Resilient per-field decoders on `SleepEvent`, `Rule`, and `RestEvent` so
  adding a new field in a future version degrades old records gracefully instead
  of wiping entire persisted arrays. `Rule.policy` absent from old JSON defaults
  to `.ignore` (never silently grants `.allow`).
- 18 new tests (245 total): decode-survival, wake-duration pairing, 24 h clamp,
  measured-minutes computation, notification de-dup, and forced-sleep/
  agent-finished opt-out coverage.

## [1.9.0] — 2026-06-22

Rest properly: sleep daily, restart weekly. A new pillar that tracks how long your
Mac has been up and recommends a restart before staleness — or the ~50-day
networking cliff — bites.

### Added
- **A "Rest & Restart" pillar.** Sleep isn't the same as a restart: sleep *pauses*
  your Mac (work held in RAM, ~0.21 W on Apple silicon); a restart *resets* it —
  clearing memory leaks and caches, resetting the kernel, WindowServer and network
  stack, and applying pending macOS updates. Decaffeinate now makes that difference
  visible and acts on it.
- **An uptime hero + restart recommendation.** A new Settings pane shows how long
  you've been up since the last restart and, when it's been a while, a calm
  recommendation — *"a restart would freshen things up"* — escalating to a real
  heads-up as uptime nears the **~49.7-day mark where macOS networking can start
  failing** (`tcp_now` overflow). Recommend-only: no buttons, no new permissions —
  you restart from the  menu on your own terms.
- **A "what each one does" explainer.** Four sourced cards spell out Display off vs
  Sleep vs Restart vs Shut down, and what each actually refreshes.
- **A rest timeline.** Forced sleeps, system sleep/wake, screen off/on and inferred
  restarts are recorded (public `NSWorkspace` events + `KERN_BOOTTIME`, capped at
  50, on-device only) so the pane can show *last sleep / last screen-rest / last
  restart* at a glance.
- **A header hint.** When a restart is due, the menu surfaces a one-line nudge below
  the awake summary — neutral for "consider", firmer (and amber) only when urgent.
- **A "Recommend a restart after N days" setting** (default 7 — the expert-consensus
  weekly cadence), with a resilient migration so existing settings are never wiped.

### Notes
- Sources behind the copy: Apple Support, Macworld, Intego, Eclectic Light, Tom's
  Hardware. Everything stays public-API-only and on-device — no root, no kernel
  extensions, no new entitlement.

## [1.8.0] — 2026-06-22

Clearer holds: stable order, audio source, lifetime, and an at-a-glance answer.

### Added
- **A lifetime indicator** on every hold — a quiet trailing mark that says whether
  it's **until done** (it'll end on its own), **timed**, or **indefinite**, plus an
  "Ends" row in the detail ("When npm finishes" / "On a timer (re-arms
  automatically)" / "No timeout — held until released").
- **A header "won't sleep until…" line** — the single most useful answer at a
  glance, e.g. *"Won't sleep while Claude Code · ~/myrepo is working"* or *"Won't
  sleep until npm finishes"*.
- **Audio source detail.** Audio holds now name **which device** is keeping the
  Mac awake — "Playing audio · **Built-in Speakers**", "Microphone in use ·
  **AirPods Pro**" — resolved via public CoreAudio (no extra permission). An
  unattributed `coreaudiod` hold is titled by its device so several audio sources
  read distinctly, with device-aware icons (AirPods / headphones / speaker).
- **Row actions** in the `…` menu: *Bring <app> to front*, *Show in Activity
  Monitor*, and *Copy details*.

### Changed
- **The list is now stably alphabetical** by the row's visible title (agent +
  project, app name, or device), with a deterministic tiebreaker — so re-spawning
  AI-agent holds no longer jump up and down between scans.

## [1.7.1] — 2026-06-21

Stop the agent-`caffeinate` churn. AI agents (Claude Code…) run `caffeinate -i -t
300`, which re-spawns a fresh process every ~5 minutes — so the menu's "held"
timer kept resetting and the list churned with ever-changing pids.

### Fixed
- **One stable row per agent session.** All of a session's churning caffeinates
  now coalesce into a single row keyed by *agent + project + terminal* — labeled
  "Claude Code · ~/myrepo" — that survives the respawns. Two projects (or two
  terminal tabs) are two distinct, stable rows; "N apps holding" counts sessions.
- **A correct "held" duration** anchored to when the *session* first started
  holding (tracked across ticks with a 90-second grace so the respawn gap doesn't
  reset it), instead of the current 5-minute process. The detail view notes
  "Re-arms automatically (caffeinate -t)".

## [1.7.0] — 2026-06-21

Transparency & agentic integration — answer *where* a keep-awake came from, and
work with the AI agents that create them.

### Added
- **Process provenance.** Decaffeinate now traces each hold back to the window /
  terminal / agent / project that started it — e.g. *"caffeinate · started by
  **Claude Code** · in **~/dev/myrepo** · ttys004"*. The expanded row shows
  *Started by*, *Folder*, *Terminal*, the exact *Command*, and *Holding since*.
  Built entirely on public `libproc` / `sysctl` (parent-chain + `cwd` + `argv`) —
  no root, no private API, no new permission.
- **Agentic awareness.** It parses a holder's `caffeinate` command line to say
  exactly what it's doing (*"Keeping the system awake until npm run build (PID
  8123) finishes"* / *"for up to 5 min"*), recognizes AI-agent sessions (Claude
  Code, Cursor, Windsurf, Aider), and — for a `caffeinate -w <pid>` hold — offers
  a one-click **"Sleep when it finishes"**. New Settings → Automation toggle
  **"Auto-sleep when a watched agent finishes"** makes that hands-off.
- **An inline "ⓘ what's keeping it awake?" explainer** that demystifies the
  numbers (what a power assertion is, that *"held 9m"* is the real age) — shown
  once, then a tap away.
- **A standard Software Update home** in Settings → About: *Check for Updates…*,
  *Automatically check for updates*, and *Last checked* — plus a *Check for
  Updates…* app-menu command. The unlabeled refresh icon is gone from the menu
  (the green "Update available" button stays).
- **`Decaffeinate --provenance [pid]`** — a terminal diagnostic that prints where
  each holder came from.

### Fixed
- **Settings no longer reset when you upgrade.** The settings decoder failed the
  whole blob on a single missing key, so every version that added a setting wiped
  your saved preferences. It now keeps defaults for absent keys.

## [1.6.0] — 2026-06-21

A ground-up design pass, grounded in **real** screenshots for the first time, with
the direction chosen from rendered options. New: a screenshot harness that captures
the live SwiftUI surfaces (`NSHostingView` + `cacheDisplay`, so `ScrollView` /
`TabView` / `Menu` render for real — `ImageRenderer` can't); a multi-agent design
council critiqued those shots and proposed two directions; **Nightcap** (cool,
native, airy) was chosen.

### Changed
- **The menu, rebuilt.** The header now *hugs* its content — the large dead gap
  between the status and **Sleep Now** is gone (it was an unbounded accent rule
  eating vertical slack). Green moved onto the action that matters (**Sleep Now**);
  the two status chips collapse to one quiet, tracked meta-line (`BATTERY 82% ·
  2 APPS HOLDING`), never amber for a normal hold; **Allowed** is now a neutral
  tag with a teal dot, not a green pill. One row pattern: at most two buttons
  (**Allow** / **Let it sleep**) plus a single `…` for the rest. A readable type
  floor throughout.
- **Settings, rebuilt as a native sidebar.** The old 8-tab strip (which clipped its
  last tab) is now a sidebar of five grouped panes — **General** (Safety folded in),
  **Schedule**, **Automation** (triggers + rules + strict takeover), **History**,
  **About** — with the brand green carried through the controls and selection, so
  Settings and the menu finally read as one product.
- **Menu-bar icon states are clearer at 18px.** The four states now separate by
  *shape*, not line-weight: crescent (free) · down-chevron (winding down) · steam
  (held) · bolt (kept awake).
- The header count and the meta-line count now agree (both speak to apps holding
  the Mac awake that you haven't allowed).

### Fixed
- **Battery-critical now also drops keep-awake holds.** At ≤3% on battery the app
  forced sleep but didn't release its hold; with a user floor set ≤3% that was a
  force-sleep-vs-hold contradiction. It now drops the hold too (matching the
  thermal-critical guard).
- **Quiet window paused by a safety rail says so.** When battery/thermal pauses a
  "stay awake until…" window, the header now reads *"Quiet window paused — <reason>"*
  instead of falling through to a misleading "Sleeping in…" countdown.

### Removed
- Stale code retired in the rebuild: the old `ImageRenderer` preview path
  (`PreviewRenderer`, `ShowcaseView`), the superseded menu views, and dead helpers
  (`Eyebrow`, `SectionHeader`, `harfExplanatory`, `harfCardChrome`, `explanatory`,
  `idleThresholdSeconds`, `OnboardingPreview`).

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
