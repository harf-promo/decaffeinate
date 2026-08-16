# Phase B feasibility spike — the optional lid-closed privileged helper

*Safe, non-live half of the timeboxed spike `docs/archive/PLAN-NEXT-1.21-1.25.md`'s v1.24
"Phase B" section calls for. Verdict of this half: the mechanism compiles,
is unit-tested via fakes, and is structurally reasoned about — but **three
of the five original ABORT criteria are, by design, not touched by this
spike and remain unverified until a real hands-on hardware test happens.**
Nothing here was executed live: no `sudo pmset disablesleep 1`, no
`SMAppService.daemon(...).register()`, no notarization submission. See the
"Hard safety constraints" this spike was run under, quoted at the end.*

## What this is answering

Decaffeinate's entire premise is root-free, user-space, no-private-API sleep
management (`docs/ARCHITECTURE.md`). The one thing that premise can't do is
keep a **closed, displayless** MacBook awake — Apple gives user space no way
to do that; the only mechanism that works at all is the undocumented,
root-only `pmset disablesleep 1` kernel flag. `docs/archive/PLAN-NEXT-1.21-1.25.md`'s v1.24
Phase B asks whether an **optional, opt-in, revocable privileged helper**
built around that flag could be engineered safely enough to ship. This spike
is the design's own prerequisite: build the non-dangerous half (does the
mechanism *compile* and hold together as a design) without doing the
dangerous half (does it actually *work* on real, closed hardware).

## What was built

| Piece | Where | Notes |
|---|---|---|
| New SwiftPM executable target `DecaffeinateLidHelper` | `Package.swift`, `Sources/DecaffeinateLidHelper/` | A separate product; `Decaffeinate` does not depend on it, import it, or invoke it. |
| `LeaseState` | `Sources/DecaffeinateLidHelper/LeaseState.swift` | Pure `Codable` value type — the XPC reply shape. |
| `DisableSleepControlling` seam | `Sources/DecaffeinateLidHelper/DisableSleepControlling.swift` | Protocol + `LiveDisableSleepController` (real, `Process`-based, **never invoked**) — mirrors `Core/SleepController.swift`'s exact protocol+real+fake shape. |
| `LidHelperLease` | `Sources/DecaffeinateLidHelper/LidHelperLease.swift` | Pure lease bookkeeping: TTL clamp (hard cap 8 h), expiry check. No XPC/IOKit inside it. |
| `LidHelperService` | `Sources/DecaffeinateLidHelper/LidHelperService.swift` | The mechanism-only coordinator: hardcodes clear-on-launch, clear-on-SIGTERM, clear-on-expiry (dead-man switch). An `actor`, driven with explicit `now` values so it's deterministic in tests. |
| `LidHelperXPCProtocol` / `LidHelperXPCService` / `LidHelperListenerDelegate` | `Sources/DecaffeinateLidHelper/` | The `@objc`/`NSXPCConnection` surface (`acquireLease`/`renewLease`/`releaseLease`/`currentState`/`helperVersion`) and its listener wiring. Structurally complete; the listener is only ever *started* in `main.swift`. |
| `main.swift` | `Sources/DecaffeinateLidHelper/main.swift` | Wires the real `LiveDisableSleepController` + `NSXPCListener` + `SIGTERM` handling. **Never executed** — this binary is never launched, by a test or otherwise, as part of this spike. |
| `LidClosedControlling` protocol | `Sources/Decaffeinate/Core/Protocols.swift` | App-side seam; not referenced by `AppState.swift` or any View. |
| `LidHelperClient`, `LidHelperReply`, `LidHelperClientXPCProtocol` | `Sources/Decaffeinate/Core/LidHelperClient.swift` | Real, XPC-calling client implementation. Compiles; never constructed anywhere in the app or its tests. Deliberately duplicates the XPC contract shape rather than importing `DecaffeinateLidHelper`, so `Decaffeinate` has zero dependency edge onto the new target (see the file's own doc comment for the tradeoff this makes). |
| `LidClosedSession` pure state machine | `Sources/Decaffeinate/Core/LidClosedSession.swift` | `armed(ttlSeconds:)` → `active(expiresAt:)` → `ending(reason:)`, mirroring `HoldLifetime`/`CaffeineEngine.ReconcileAction`'s pure-transition shape. |
| Embedded `LaunchDaemon` plist | `Resources/com.harfpromo.Decaffeinate.LidHelper.plist` | Static resource. Not copied by `Scripts/build-app.sh`, not referenced by any `SMAppService` call. |
| Tests | `Tests/DecaffeinateLidHelperTests/*`, plus `LidClosedSessionTests.swift` / `LidHelperClientTests.swift` in `Tests/DecaffeinateTests/` | See "Test count" below. All fake-driven; `LiveDisableSleepController.setDisableSleep`, `LidHelperClient`'s real XPC calls, and `SMAppService.daemon(...).register()` are **not called by any test**. |

## ABORT criteria — status

The original design (`docs/archive/PLAN-NEXT-1.21-1.25.md`) named five ABORT criteria. This is
exactly what this spike could and couldn't touch without crossing its own
hard safety constraints:

| # | Criterion | Status | Verified how |
|---|---|---|---|
| (a) | `SMAppService` daemon registration + approval works on the non-Xcode `build-app.sh` bundle | **Not live-tested.** Code compiles; embedding location structurally reasoned about. | See "SMAppService.daemon embedding" below. `SMAppService.daemon(...).register()` is never called — constraint #2. |
| (b) | `disablesleep 1` empirically holds a closed, displayless Apple Silicon MacBook awake on current macOS | **Not live-tested — cannot be verified without physically closing this machine's lid with the flag set, which this spike deliberately did not do.** | Reasoned about only, from `docs/ARCHITECTURE.md`'s existing non-goals and public folklore (see below). `sudo pmset disablesleep 1` is never run — constraint #1. |
| (c) | Reboot behavior of the flag | **Not live-tested.** | Same reasoning limits as (b) — no reboot was performed against a live flag. |
| (d) | Notarization of the embedded helper passes | **Not attempted** (constraint #3 forbids real `notarytool submit`). Local, no-notarization signing sanity check done instead. | `codesign --verify --deep --strict` on an ad-hoc-signed standalone build of the helper binary — see "Local signing sanity check" below. |
| (e) | Cheap re-check of Amphetamine's claimed public API | **Done, via research (WebSearch/WebFetch).** | See "Amphetamine re-check" below. |

**Bottom line: (a), (b), and (c) are exactly the three criteria that require
a live hardware test with the owner's explicit participation — closing a
real lid, approving a real System Settings prompt, physically rebooting —
before any Phase B go/no-go decision. This spike could not and did not
attempt to close that gap; that was the point of splitting the spike into a
safe and a live half.**

## SMAppService.daemon embedding — investigation

**Conclusion: `.daemon` plists live at `Contents/Library/LaunchDaemons/<label>.plist`
inside the app bundle; `.agent` plists live at `Contents/Library/LaunchAgents/<label>.plist`.
Neither goes to `Contents/XPCServices/`** (that directory is for the older,
unrelated "XPC Services" app-extension mechanism, not for an
`SMAppService`-registered `launchd` job). The daemon's executable is
conventionally placed alongside the main app binary, at
`Contents/MacOS/DecaffeinateLidHelper`.

Sources and confidence: Apple's own `SMAppService` documentation page
(`developer.apple.com/documentation/servicemanagement/smappservice`) is
JavaScript-rendered and did not return usable body text through this spike's
fetch tooling — **that specific primary source could not be directly quoted
here**. The conclusion above is corroborated by three independent secondary
sources that were fetched successfully and agree with each other and with
this codebase's own general `SMAppService` knowledge (`LoginItem.swift`
already uses `SMAppService.mainApp` for the unprivileged login-item case):

- [theevilbit's SMAppService blog post](https://theevilbit.github.io/posts/smappservice/) — shows a concrete example path,
  `Contents/Library/LaunchDaemons/com.csabafitzl.ScriptRunner.helper.plist`,
  and states plainly that with `SMAppService`, "launch daemons and their
  associated plist files are expected to be within the application bundle
  itself" (not moved to `/Library/LaunchDaemons/` the way the older
  `SMJobBless` approach worked).
- An [Apple Developer Forums thread](https://developer.apple.com/forums/thread/771162) with a reply from an Apple DTS engineer —
  the one genuinely new, non-obvious finding of this research: the daemon's
  plist can use either a `BundleProgram` key (a bundle-relative path) *or*
  the classic `Program`/`ProgramArguments` keys (an absolute path), but
  **`BundleProgram` is only honored when the daemon was registered
  interactively via `SMAppService.daemon(...)` itself** — a script/pkg-driven
  install path needs `Program`/`ProgramArguments` instead. The embedded
  `Resources/com.harfpromo.Decaffeinate.LidHelper.plist` in this repo uses
  `ProgramArguments` (per this task's own spec) and documents this nuance
  inline as an XML comment.
- A WWDC22 "What's new in privacy" session summary, cross-referenced via
  search — consistent with the above: `SMAppService` (introduced in macOS
  Ventura to replace `SMJobBless`/`SMLoginItemSetEnabled`) keeps daemon/agent
  plists inside the app bundle so no separate installer or cleanup script is
  needed, and confirms the `Contents/Library/LaunchDaemons/` path.

**Entitlements**: reasoned about, not confirmed against Apple's primary
documentation (same JS-rendering limitation as above). What's fairly
confident: the helper does not need `com.apple.security.app-sandbox` (a
`LaunchDaemon` isn't sandboxed the way an app extension is — matches this
app's own non-sandboxed `Resources/Decaffeinate.entitlements`), and needs no
special entitlement to shell out to `/usr/bin/pmset` (the same reasoning
`docs/ARCHITECTURE.md` already applies to the main app's `SleepController`).
What's less certain and would need direct confirmation before shipping: (1)
whether the helper executable must be signed with the exact same Developer
ID / Team Identifier as the main app for `SMAppService.daemon` to accept the
registration (widely reported as a hard requirement in community sources,
consistent with how the older `SMJobBless`'s `SMAuthorizedClients` matching
worked, but not independently confirmed here against Apple's own page); (2)
whether `SMAppService`-registered daemons still need any `Info.plist`
declaration at all beyond the embedded `LaunchDaemons` plist (community
sources say no additional `Info.plist` keys are required, unlike the old
`SMJobBless`'s `SMPrivilegedExecutables`/`SMAuthorizedClients` pair, but this
too is secondhand).

### What `Scripts/build-app.sh` would need (not implemented)

`Scripts/build-app.sh` was **read in full, not modified**. It already
performs an inside-out signing pattern for `Sparkle.framework` (sign nested
binaries first, then the whole `.app` once) that a real embedding step would
extend, not replace:

1. Build `DecaffeinateLidHelper` alongside `Decaffeinate` (`swift build -c
   "${CONFIG}" --arch ... ` — the script already resolves `BIN_DIR` for the
   main executable; the helper's binary would come from the same
   `swift build --show-bin-path` output directory).
2. `mkdir -p "${APP_BUNDLE}/Contents/Library/LaunchDaemons"`, copy
   `Resources/com.harfpromo.Decaffeinate.LidHelper.plist` there.
3. Copy the built `DecaffeinateLidHelper` binary to
   `${APP_BUNDLE}/Contents/MacOS/DecaffeinateLidHelper`.
4. In the `DEVELOPER_ID` signing branch, sign the helper binary **before**
   the final whole-bundle `codesign` call — same inside-out ordering the
   Sparkle loop already uses (notarization requires every nested Mach-O
   signed) — with `--options runtime --timestamp --sign "${DEVELOPER_ID}"`,
   and whatever helper-specific entitlements turn out to be needed (probably
   none beyond hardened runtime, per the reasoning above — needs
   confirmation).
5. Re-run `codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"`
   (the script already does this in the Developer ID branch) — this would
   now also validate the newly nested daemon.

None of this was written into `build-app.sh` — this is a documentation
deliverable only, per this task's own instructions.

### Local signing sanity check (done, no notarization)

The standalone helper binary was built and ad-hoc signed directly (outside
`build-app.sh`, which was not touched):

```
$ swift build --target DecaffeinateLidHelper
$ codesign --force --sign - .build/arm64-apple-macosx/debug/DecaffeinateLidHelper
$ codesign --verify --deep --strict --verbose=2 .build/arm64-apple-macosx/debug/DecaffeinateLidHelper
.../DecaffeinateLidHelper: valid on disk
.../DecaffeinateLidHelper: satisfies its Designated Requirement
```

This confirms the binary itself has no structural signing blocker (no
malformed Mach-O, no missing/broken code directory) — but ad-hoc signing
does **not** exercise the hardened-runtime + entitlements + Developer-ID
Team-ID-matching path a real `SMAppService.daemon` registration needs, and
real notarization (`notarytool submit`) was correctly never attempted here
per constraint #3.

## `disablesleep` — reasoning, not live-tested

`docs/ARCHITECTURE.md`'s existing non-goals section already states the
relevant negative knowledge, reaffirmed rather than re-derived here: the
private in-process alternatives (`RootDomainUserClient` selector 12,
`IORegistryEntrySetCFProperty`, `IOPMSetSystemPowerSetting`) were
field-verified by the Adrafinil project to all fail on real hardware; only
`pmset disablesleep` (root-only, undocumented by Apple, folklore-documented
by tools like Adrafinil and various keep-awake utilities) is reported to
actually work. Nothing in this spike adds new evidence either way — the two
open empirical questions from the original design remain exactly as open as
before:

- **Does it actually hold a real, closed, displayless Apple Silicon
  MacBook awake?** Not verifiable without live testing — this spike
  deliberately did not close this machine's lid with the flag set.
- **Does it persist across reboot** (i.e., does the flag survive, or does
  something clear it, and does `RunAtLoad` reliably re-clear a stray set
  flag on the next boot)? Not verifiable without a live reboot test.

## Amphetamine re-check

Re-checked via `WebSearch`/`WebFetch` (no MAS purchase, no login). Findings:

- The specific claim — *"Amphetamine achieves this by using a
  publicly-accessible API to disable Apple's requirements and enable
  Closed-Display Mode under any circumstance"* — is real and still appears
  in Amphetamine's own support material, but that material lives on a
  Freshdesk-hosted knowledge base
  (`iffy.freshdesk.com/support/solutions/articles/48001077199-amphetamine-closed-display-mode`)
  that is **behind a login wall**: every direct `WebFetch` attempt at that
  URL (and a related article,
  `.../48001180528-about-failed-closed-display-mode-sessions`) redirected to
  a Freshworks OAuth authorization page. **This spike could not get past
  that wall and is not claiming to have read the primary source directly** —
  the quote above is corroborated only via search-engine-indexed snippets of
  that page, not a page fetch. This matches this project's prior research
  finding that the claim is "under-documented."
- Independent of the wall, Amphetamine's own public GitHub repositories
  contradict the "under any circumstance" framing in practice on Apple
  Silicon: starting with Amphetamine 5.3, Closed-Display Mode requires a
  **separately-installed script + config pair called "Power Protect"**
  ([x74353/Amphetamine-Power-Protect](https://github.com/x74353/Amphetamine-Power-Protect)),
  specifically to work around a documented failure mode — "Closed-Display
  Mode may not work as expected after connecting or disconnecting your Mac
  from an external power source" on Apple Silicon laptops. Installing Power
  Protect itself requires Touch ID or admin-password authentication, and the
  README states plainly that **"Apple won't allow Amphetamine to directly
  install the script and configuration file"** — i.e. whatever the
  "publicly-accessible API" is, it is not sufficient by itself on Apple
  Silicon without an additional, authenticated, out-of-band install step.
- Community-reported fragility: a GitHub issue on the companion
  "Amphetamine Enhancer" project reports the "Closed-Display Mode Fail-Safe"
  feature missing/inaccessible on an M2 MacBook Pro
  ([x74353/Amphetamine-Enhancer#25](https://github.com/x74353/Amphetamine-Enhancer/issues/25)),
  and a "Power Protect Failure" issue recurs in the Power Protect repo's own
  issue tracker.
- **Conclusion: nothing found here overturns this project's prior
  conclusion.** Amphetamine's mechanism is real in some form, but it is not
  a clean, sandbox-safe, no-privileged-anything story on Apple Silicon — it
  needs its own separately-installed, authenticated helper script, and its
  own community reports it as unreliable around power-source transitions.
  This is consistent with (not proof of, given the login wall) `docs/ARCHITECTURE.md`'s
  characterization of `kIOPMAssertionAppliesOnLidClose` as entitlement-gated
  territory that killed at least one competitor (Fermata) outright, and
  doesn't change this project's own root-free non-goal.

## Test count

- **Before:** 454 tests (the stated baseline; confirmed via a clean
  `swift test` run before any change in this spike).
- **After:** 486 tests (+32), all passing, 0 failures.
  - `Tests/DecaffeinateLidHelperTests/` (new target): 21 tests —
    `LidHelperLeaseTests` (pure TTL clamp/expiry bookkeeping),
    `LidHelperServiceTests` (fake-`DisableSleepControlling`-driven: acquire/
    renew/release, the dead-man switch, clear-on-launch, clear-on-SIGTERM),
    `LeaseStateTests` + `DisableSleepErrorTests` (value-type/JSON round trip).
  - `Tests/DecaffeinateTests/` (existing target, new files): 11 tests —
    `LidClosedSessionTests` (every `armed`/`active`/`ending` transition),
    `LidHelperReplyTests` + `LidClosedControllingSeamTests` (JSON round trip,
    fake-conforms-to-protocol seam check).
  - No test in either target constructs `LiveDisableSleepController` and
    calls it, constructs `LidHelperClient` and calls its XPC methods, or
    calls `SMAppService.daemon(...).register()` / `.unregister()`.

## Hard safety constraints this spike ran under

Quoted from the task brief this spike was executed against, for the record:
never run `sudo pmset disablesleep 1` for real; never call
`SMAppService.daemon(...).register()`/`.unregister()` against the live
system; never submit anything to Apple's real notarization service; the new
helper target must not be wired into the shipped app's normal run path at
all. All four were followed throughout — see the "what was and wasn't done"
notes inline above for exactly where each constraint bit.

## What the owner needs to decide next

This spike answers "does the design hold together on paper and in code" —
it does. It does **not** and cannot answer whether Phase B should actually
ship, because that requires the three live-hardware criteria above:

1. Build a Developer-ID-signed (not necessarily notarized yet) test build
   with the helper actually wired into `build-app.sh`, and confirm
   `SMAppService.daemon(...).register()` produces the expected System
   Settings approval prompt and the daemon actually starts.
2. With the owner physically present: close this machine's lid with no
   external display, with the flag set by the (now-running, approved)
   helper, and confirm the Mac actually stays awake and responsive over the
   network for a meaningful period.
3. Reboot the machine with the flag set and confirm both that the flag's
   behavior across reboot is as expected and that `RunAtLoad` reliably
   re-clears any stray state on the next boot.

Any failure on any of these three is a hard abort back to Tier 1 (the
already-shipped, zero-root Clamshell Assistant) plus the transparency page —
exactly as `docs/archive/PLAN-NEXT-1.21-1.25.md` already specifies.
