# Architecture

Decaffeinate is an honest macOS menu-bar app. Everything runs in user space
using public APIs — no root, no kexts, no private SPI. This document explains
how the pieces fit so you can contribute with confidence.

## The big picture

```
                  ┌────────────────────────────────────────────┐
                  │                SwiftUI UI                   │
                  │  MenuBarExtra (RedesignMenuView: RDHeader · │
                  │  RDActionBar · RDList · RDRow · RDFooter)   │
                  │  Settings (sidebar: General · Schedule ·    │
                  │  Automation · Rest&Restart · History·About) │
                  │  OnboardingView (first run)                 │
                  └───────────────────┬─────────────────────────┘
                                      │ @Published state
                  ┌───────────────────▼─────────────────────────┐
                  │                 AppState                     │  ← @MainActor coordinator
                  │        ticks once a second:                  │
                  │        scan → sense → evaluate → act         │
                  └──┬──────┬──────┬──────┬──────┬──────┬───────┘
        sense ──────┤      │      │      │      │      ├────── act
  TelemetryEngine   │ IdleMonitor │ PowerSource │ SafetyRails   CaffeineEngine
  (IOPMCopyAsser-   │ (CGEventSrc │ (IOPSCopy…) │ (pure logic)  (IOPMAssertion…)
  tionsByProcess)   │  HID idle)  │             │               SleepController
                    │             │             │               (pmset sleepnow)
        enrich ─────┤             │   decide ───┤               Notifier (UNUser…)
  ReasonEngine · AssertionAttributor            │
  ProcessProvenanceResolver · OriginRegistry    │  SleepOutlook (single UI verdict)
  AudioDeviceResolver · HoldGroup/HoldLifetime  │  RulesEngine · ScheduleEngine
  AgentWatcher/ProcessWatcher                   │  TriggerEngine · RestartAdvisor
```

## The tick loop

`AppState.tick()` runs every second on the main actor and is the heart of the
app. Each tick:

1. **Scan** — `TelemetryEngine.scan()` lists every power assertion, attributed
   to its owning process (name + bundle id + the *real* owner behind shared
   daemons like `coreaudiod`/`runningboardd`). Decaffeinate's **own** pid is
   filtered out so the app can never report itself as a blocker.
2. **Sense** — idle time (`IdleMonitor`), power source (`PowerSourceReader`),
   thermal pressure (`ProcessInfo.thermalState`).
3. **Evaluate** — `SafetyRails.evaluate(...)` turns those signals into a pure
   `SafetyDecision`: must-sleep-now reasons, drop-keep-awake reasons, and
   hold-off reasons. An active-hours schedule (`ScheduleEngine`) can append a
   hold-off — but never blocks a battery/thermal rail.
4. **Triggers** — when trigger rules exist, `TriggerEngine` decides whether a
   conditional keep-awake (app running / on AC / CPU busy) is holding.
5. **Reconcile keep-awake** — `CaffeineEngine.update(...)` idempotently holds
   or releases IOKit assertions for: the keep-awake toggle, strict takeover
   (only while the master switch is on), an active quiet window, and triggers —
   all dropped the moment a safety rail demands it.
6. **Firewall** — surface newly-seen, unclassified blockers for an
   Allow/Block decision (`pendingClassification` + a notification).
7. **Session tracking** — coalesce churning agent `caffeinate -t` respawns
   into stable `HoldGroup` rows (keyed agent + project + tty, with a grace
   period so a respawn gap doesn't reset "held since").
8. **Sleep feedback** — a user's Sleep Now that never actually slept surfaces
   an error; stale errors expire.
9. **Agent watcher** — optionally auto-arm on a recognized agent's
   `caffeinate -w`, then advance the completion state machine
   (`AgentWatcher` over `ProcessWatcher` subtree CPU samples).
10. **Immediate guards** — overheating / critically-low battery ⇒ sleep now,
    regardless of the master switch (with its own short cooldown).
11. **Idle force-sleep (the headline)** — if auto-sleep is on, nothing the user
    wants awake is *actually* holding (keep-awake/quiet window/trigger all
    count only while the rails permit them), the idle threshold has passed, and
    no hold-off applies → `pmset sleepnow`. A watched agent's completion
    collapses the threshold to a short grace. A 60-second post-wake grace stops
    an instant re-sleep after any wake.
12. **Publish** — `SleepOutlook.classify(...)` folds everything into the ONE
    "will my Mac sleep?" value that the header, banner, every row verdict, and
    the menu-bar icon project from — so they can never contradict each other.

Steps 1–4 are cheap and in-process (no subprocesses, no polling of external
tools), so the tick is fast and safe to run every second. Provenance resolution
(the expensive part) is lazy — it runs on row render, never in the tick.

## Engine map

| Area | Types | Job |
| --- | --- | --- |
| Scan & attribute | `TelemetryEngine`, `AssertionAttributor`, `SystemNames` | Enumerate assertions; trace daemon-routed holds to the real app. |
| Explain | `ReasonEngine`, `AudioDeviceResolver` | Classify each hold into plain English (incl. mic/media via `ResourcesUsed`); name the audio device. `ReasonEngine.sanitize` guards all app-controlled free text. |
| Provenance | `ProcessProvenance(-Resolver)`, `OriginRegistry` | Walk the parent chain (public `libproc`/`sysctl`) to "started by Claude Code · in ~/dev/myrepo". Cached by pid+start-time (pid-reuse safe), TTL'd, periodically swept. |
| Agent awareness | `CaffeinateInvocation`, `AgentRegistry`, `AgentWatcher`, `ProcessWatcher` | Parse `caffeinate -w/-t/…`; recognize AI-agent sessions; watch a subtree's CPU (exited children's CPU is retained) and declare completion. |
| Decide | `SafetyRails`, `ScheduleEngine`, `TriggerEngine`, `RulesEngine`, `SleepOutlook`, `HoldLifetime`/`HoldGroup`, `RestartAdvisor` | Pure, unit-testable decision logic — from safety rails to the single UI verdict. |
| Act | `SleepController` (pmset), `CaffeineEngine` (IOKit holds), `Notifier`, `LoginItem`, `UpdaterController` (Sparkle) | The only pieces with side effects; each is thin. |
| Persist | `SettingsStore`, `RulesEngine`, `SleepHistoryStore`, `RestHistoryStore` | `UserDefaults` JSON blobs with field-level resilient decoding (a new field never wipes saved state). |
| Automate | `AppIntents`, `AutomationURL`, `CLI`, KeyboardShortcuts | Shortcuts/Siri/Spotlight, `decaffeinate://`, `--scan/--sleep-now/--keep-awake/--provenance`, global hotkey. |

## Why these APIs

| Job | API | Notes |
| --- | --- | --- |
| Enumerate assertions | `IOPMCopyAssertionsByProcess` | Public IOKit; same data as `pmset -g assertions`. |
| Resolve process names | `proc_pidpath` / `proc_name` / `NSRunningApplication` | Friendly names + bundle ids + icons. |
| Provenance / argv / cwd | `libproc` (`proc_pidinfo`, `PROC_PIDVNODEPATHINFO`), `sysctl` (`KERN_PROCARGS2`) | Public, no root; argv sanitized before display. |
| Subtree CPU | `proc_listallpids` + `PROC_PIDTASKINFO` | Drives agent-completion detection. |
| Idle time | `CGEventSource.secondsSinceLastEventType` | Duration only; never event content. |
| Battery | `IOPSCopyPowerSourcesInfo` | Charge %, on-battery, charging. |
| Thermal | `ProcessInfo.thermalState` | Public, clean Backpack-Guard signal. |
| CPU triggers | Mach `host_statistics` (`HOST_CPU_LOAD_INFO`) | System-wide CPU % deltas. |
| Audio device names | CoreAudio (`AudioObjectGetPropertyData`) | "AirPods Pro", "Built-in Microphone". |
| Force sleep | `/usr/bin/pmset sleepnow` | No root; the normal kernel sleep transition. |
| Keep awake | `IOPMAssertionCreateWithName` | Standard prevent-idle-sleep assertion. |
| Launch at login | `SMAppService.mainApp` | Status re-read from the OS, never trusted from a cache. |
| Boot time / uptime | `sysctl KERN_BOOTTIME` | Rest & Restart's anchor. |
| Updates | Sparkle (EdDSA-signed appcast) | The app's only network request; optional. |

A note on **forcing sleep**: macOS sandboxes assertions so a process can only
release assertions *it* created. Decaffeinate never tries to release another
app's assertion. Instead it leaves them in place and triggers a real system
sleep via `pmset` — the kernel transitions to sleep regardless of outstanding
"prevent idle sleep" holds. That's why the design is robust without any
privileged access.

## Safety detection without subprocesses

Time Machine backups, software updates, and active media all register their own
power assertions. Rather than shelling out to `tmutil`/`softwareupdate` on every
tick, `SafetyRails` detects them from the same assertion snapshot the scanner
already produced — matched by the **verified owning process**, never the
caller-controlled assertion name (any app could register a hold named "Backup"
to dodge force-sleep). One read, many signals.

## Concurrency model

The app is Swift 6 strict-concurrency clean. The coordinator and every stateful
engine (`AppState`, `SettingsStore`, `RulesEngine`, `CaffeineEngine`,
`Notifier`, `AgentWatcher`, `ProcessWatcher`, `ProcessProvenanceResolver`,
`AudioDeviceResolver`, the history stores, `UpdaterController`) are
`@MainActor`. The per-second timer is pinned to the main run loop in `.common`
modes (so it keeps ticking while the menu is open) and re-enters the main actor
via `MainActor.assumeIsolated`. The sensing engines (`TelemetryEngine`,
`IdleMonitor`, `PowerSourceReader`, `SleepController`) are value types with no
shared mutable state, and the decision layer (`SafetyRails`, `ScheduleEngine`,
`TriggerEngine`, `SleepOutlook`, `RestartAdvisor`, `HoldLifetime`) is pure —
which is what makes the suite's 300+ tests possible without a GUI.

## Distribution

Because Decaffeinate spawns `pmset` and reads system-wide telemetry, it cannot
run inside the App Store sandbox. It ships as a **Developer-ID-signed,
notarized DMG** with **Sparkle auto-update** and a **Homebrew cask**
(`brew install --cask decaffeinate` via the `harf-promo/tap`), all built by the
tag-triggered release workflow. Dependencies are pinned via a committed
`Package.resolved`. See [`DISTRIBUTION.md`](DISTRIBUTION.md).

## Non-goals & negative knowledge

- **Keeping a Mac awake with the lid closed.** Requires `pmset -a disablesleep`
  — a global, persistent, root-only footgun. Field-verified by the Adrafinil
  project (which built a root helper for exactly this): the in-process
  alternatives — the private `RootDomainUserClient` selector 12,
  `IORegistryEntrySetCFProperty`, and `IOPMSetSystemPowerSetting` — **all fail**
  to block clamshell sleep on real hardware; only `disablesleep` works, and it
  then needs multiple safety layers (clear-on-start/SIGTERM, dead-man switch)
  against stranding the Mac awake. Decaffeinate stays root-free; don't re-spend
  time here.
- **Releasing other apps' assertions.** Not possible from user space, and not
  needed — `pmset sleepnow` overrides them cleanly (see above).
- **App Store distribution** — incompatible with spawning `pmset` and reading
  system-wide telemetry.
- **Camera-in-use detection** — unlike the microphone (`audio-in` resource),
  there is no public assertion signal for the camera; not pursuing.
