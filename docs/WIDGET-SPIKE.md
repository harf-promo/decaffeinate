# Widget / Control Center feasibility spike (v1.23 "Glanceable", item 11)

*Time-boxed investigation (~30 min), not an implementation. Verdict: **defer**.*

## The question

Can a `WidgetKit` desktop widget or a macOS 15 Control Center `ControlWidget`
be added to Decaffeinate without abandoning the hand-assembled SwiftPM `.app`
bundle pipeline (`Scripts/build-app.sh`), given that the app already ships 4
App Intents (`Core/AppIntents.swift`) that could back either?

## What a widget/control extension needs, structurally

Both WidgetKit widgets and Control Center controls ship as a macOS **app
extension**: a separate Mach-O executable embedded as a
`Contents/PlugIns/<Name>.appex` bundle inside the host `.app`, with:

1. Its own `Info.plist` declaring `NSExtensionPointIdentifier` (WidgetKit:
   `com.apple.widgetkit-extension`) and an `NSExtensionPrincipalClass` /
   `NSExtensionMainStoryboard`-equivalent entry point.
2. Independent code-signing of the `.appex`, nested *inside* the signed seal
   of the outer `.app` (same inside-out signing order `build-app.sh` already
   does for `Sparkle.framework` — see the `DEVELOPER_ID` signing branch).
3. A shared bundle-ID namespace (`<host-id>.<extension-suffix>`) and,
   typically, matching entitlements/App Group if the extension needs to read
   live state from the host app rather than just invoking an App Intent.
4. For a **Control Center control** specifically: macOS **15 Sequoia**
   (`ControlWidget`/`ControlCenter` API). The package's current floor is
   macOS 14 (`Package.swift`: `.macOS(.v14)`) — a Control Center control alone
   would force a deployment-target bump, separate from the packaging problem.

## What this repo's pipeline has today

- **`Package.swift`** declares exactly one product: `.executable(name:
  "Decaffeinate", …)`. Swift Package Manager, as of the Swift 6 toolchain
  installed here (`swift package tools-version` → 6.0.0), has **no product
  type for an app extension** — `PackageDescription`'s `Product` cases cover
  libraries, executables, and plugins, nothing shaped like an `.appex`.
  `appintentsmetadataprocessor` (used by `build-app.sh` for Shortcuts/Siri
  discovery) is itself an Xcode-toolchain binary that SwiftPM's own `swift
  build` doesn't invoke — `build-app.sh` already runs it as a manual
  post-build step, guarded to no-op if it fails. There's no equivalent
  "assemble and sign an `.appex`" tool that operates on a bare SwiftPM binary.
- **`Scripts/build-app.sh`** copies exactly one executable into
  `Contents/MacOS/`, copies SwiftPM resource bundles into `Contents/Resources/`,
  optionally embeds `Sparkle.framework` under `Contents/Frameworks/`, and
  code-signs the whole `.app` once (or per-nested-item for the Developer ID
  path). It has **no `Contents/PlugIns/` step at all** — nothing today embeds,
  signs, or manifests a second bundle inside the app.
- **`Core/AppIntents.swift`** already has a comment recording a related,
  earlier constraint: the intents "must live in the executable target (not a
  library) for the metadata extractor to find them." That means the 4
  existing intents aren't factored into a shared library product a widget
  extension could simply `import` — sharing them would require restructuring
  `Package.swift` into a shared library target plus two executable targets
  (main app + widget), which is itself a second, separate refactor before the
  extension-packaging problem is even addressed.

## Would the existing App Intents back it if packaging were solved?

Yes, in principle — `SleepNowIntent`, `WhatsKeepingMacAwakeIntent`,
`KeepAwakeIntent`, and `StopKeepingAwakeIntent` are already self-contained
(`SleepNowIntent`/`WhatsKeepingMacAwakeIntent` don't even need the live
`AppState`; they instantiate `SleepController`/`TelemetryEngine` directly) —
exactly the shape a `ControlWidget`/`AppIntentConfiguration` widget wants.
That part is *not* the blocker; the packaging is.

## Verdict: defer

Every piece needed — an app-extension-shaped SwiftPM product, an `.appex`
assembly + nested-signing step in `build-app.sh`, and a code-sharing
restructure so the extension can reuse `AppIntents.swift` — is either
unsupported by SwiftPM outright or a nontrivial addition to a pipeline that
already carries several "guarded, fail loudly if missing" steps (App Intents
metadata, localization bundle presence, Sparkle framework signing). Stacking
a hand-rolled extension-signing step on top raises the same maintenance risk
class as those existing guards, for a feature this milestone's own planning
doc already flagged as the risky item.

- **Size estimate:** L on the current pipeline (matches the plan doc's own
  flag) — most of the cost is bespoke `.appex` assembly/signing shell code
  with no upstream tooling support, not the widget's own SwiftUI content.
- **If the project ever migrates to an Xcode project** (e.g. forced by some
  other notarization/signing need), a widget extension becomes comparatively
  cheap — Xcode's "Widget Extension" target template generates the
  `Info.plist`, `.appex` embedding, and signing wiring automatically, and the
  existing App Intents can be added to the new target with minimal change.
- **Recommendation:** defer. Don't attempt on the current hand-assembled
  pipeline. Revisit if/when an Xcode project migration happens for another
  reason; at that point this becomes a small addition instead of a bespoke
  packaging project.
