# Architecture

Decaffeinate is a small, honest macOS menu-bar app. Everything runs in user
space using public APIs. This document explains how the pieces fit so you can
contribute with confidence.

## The big picture

```
                       ┌──────────────────────────────┐
                       │         SwiftUI UI            │
                       │  MenuBarExtra · Settings      │
                       │  StatusCard · AssertionList   │
                       └──────────────┬───────────────┘
                                      │ @Published state
                       ┌──────────────▼───────────────┐
                       │           AppState            │  ← @MainActor coordinator
                       │  ticks once a second:         │
                       │   scan → evaluate → act        │
                       └───┬───────┬───────┬───────┬───┘
            ┌──────────────┘       │       │       └───────────────┐
   ┌────────▼────────┐   ┌─────────▼──┐ ┌──▼──────────┐  ┌──────────▼────────┐
   │ TelemetryEngine │   │ IdleMonitor │ │ SafetyRails │  │  RulesEngine      │
   │ IOPMCopyAsser-  │   │ CGEventSrc  │ │ pure logic  │  │  whitelist/black- │
   │ tionsByProcess  │   │ idle secs   │ │ (testable)  │  │  list + persist   │
   └─────────────────┘   └─────────────┘ └─────────────┘  └───────────────────┘
            │                                   │
   ┌────────▼────────┐   ┌──────────────┐ ┌─────▼────────┐ ┌──────────────────┐
   │ CaffeineEngine  │   │ PowerSource  │ │ SleepCtrl    │ │  Notifier        │
   │ IOPMAssertion-  │   │ IOPowerSrc   │ │ pmset        │ │  UNUserNotif      │
   │ CreateWithName  │   │ battery info │ │ sleepnow     │ │  (best-effort)    │
   └─────────────────┘   └──────────────┘ └──────────────┘ └──────────────────┘
```

## The tick loop

`AppState.tick()` runs every second on the main actor and is the heart of the
app. Each tick:

1. **Scan** — `TelemetryEngine.scan()` lists every power assertion, attributed to
   its owning process (name + bundle id).
2. **Sense** — read idle time (`IdleMonitor`), power source (`PowerSourceReader`),
   and thermal pressure (`ProcessInfo.thermalState`).
3. **Evaluate** — `SafetyRails.evaluate(...)` turns those signals into a pure
   `SafetyDecision`: must-sleep-now reasons, drop-keep-awake reasons, and
   hold-off reasons.
4. **Reconcile keep-awake** — `CaffeineEngine.update(...)` idempotently holds or
   releases assertions to match the desired state (caffeine and/or takeover,
   minus any safety drop).
5. **Firewall** — surface newly-seen, unclassified blockers for an Allow/Block
   decision.
6. **Act** —
   - If a must-sleep guard fired (overheating / critical battery), sleep now.
   - Else, if Decaffeinate is enabled, not caffeinating, idle past threshold, and
     no hold-off reason applies → `pmset sleepnow`.
7. **Publish** — compute the derived UI state (mug icon, headline, countdown).

Because steps 1–3 are cheap and in-process (no subprocesses, no polling of
external tools), the tick is fast and safe to run every second.

## Why these APIs

| Job | API | Notes |
| --- | --- | --- |
| Enumerate assertions | `IOPMCopyAssertionsByProcess` | Public IOKit; same data as `pmset -g assertions`. |
| Resolve process names | `proc_pidpath` / `proc_name` / `NSRunningApplication` | Friendly names + bundle ids + icons. |
| Idle time | `CGEventSource.secondsSinceLastEventType` | Duration only; never event content. |
| Battery | `IOPSCopyPowerSourcesInfo` | Charge %, on-battery, charging. |
| Thermal | `ProcessInfo.thermalState` | Public, clean Backpack-Guard signal. |
| Force sleep | `/usr/bin/pmset sleepnow` | No root needed; normal kernel sleep transition. |
| Keep awake | `IOPMAssertionCreateWithName` | Standard prevent-idle-sleep assertion. |
| Launch at login | `SMAppService.mainApp` | macOS 13+. |

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
already produced (by owning process and assertion name). One read, many signals.

## Concurrency model

The app is Swift 6 strict-concurrency clean. UI and coordinator types
(`AppState`, `SettingsStore`, `RulesEngine`, `CaffeineEngine`, `Notifier`) are
`@MainActor`. The per-second timer is pinned to the main run loop in `.common`
modes (so it keeps ticking while the menu is open) and re-enters the main actor
via `MainActor.assumeIsolated`. The stateless engines (`TelemetryEngine`,
`IdleMonitor`, `PowerSourceReader`, `SleepController`) are value types with no
shared mutable state, and `SafetyRails` is a stateless namespace of pure static
functions.

## Distribution

Because Decaffeinate spawns `pmset` and reads system-wide telemetry, it cannot
run inside the App Store sandbox. It ships as open source you build yourself, and
(on the roadmap) as a Developer-ID-signed, notarized DMG and a Homebrew cask.
See [`DISTRIBUTION.md`](DISTRIBUTION.md).
