# Localization

Decaffeinate ships English plus a **seed German** translation of the onboarding
and About surfaces. This is scaffolding — a working template so contributors can
add languages and widen coverage. 🙋 Translations are a great first PR.

## How it works (read this first)

Translatable strings live in per-language tables under
`Sources/Decaffeinate/Resources/<lang>.lproj/Localizable.strings`. With
`defaultLocalization: "en"` set in `Package.swift`, SwiftPM compiles them into the
executable target's **own** resource bundle — `Bundle.module`
(`Decaffeinate_Decaffeinate.bundle`), which `build-app.sh` copies into the `.app`.

**The catch:** SwiftUI's `Text("literal")` localizes against `Bundle.main` (the
`.app`), which never sees a SwiftPM module bundle. So a raw `Text("Welcome")` is
**not** localized, even with a matching table entry. Strings must resolve through
`Bundle.module` explicitly, via the one helper:

```swift
Text(L10n.localized("Welcome"))          // ✅ localized
Button(L10n.localized("Skip")) { … }     // ✅ works for Button/Toggle/Label/.help too
Text("Welcome")                          // ❌ always English
```

`L10n` lives in `Sources/Decaffeinate/Core/Localization.swift`. It's the single
path used for `Text`, `Button`, `Toggle`, `Label`, `.help(_:)`, and `NSWindow`
titles — none of which take a `bundle:` parameter. A missing key falls back to the
English source text (the key itself), never an empty string.

## Add a language

1. Copy `Sources/Decaffeinate/Resources/en.lproj/Localizable.strings` to a new
   `<code>.lproj/Localizable.strings` (e.g. `fr.lproj`, `es.lproj`) and translate
   the right-hand values. Keys are the English source and must stay verbatim.
2. Add the language code to `CFBundleLocalizations` in `Resources/Info.plist`.
3. Mirror a couple of assertions in `Tests/DecaffeinateTests/LocalizationTests.swift`
   so a dropped table is caught in CI.
4. `swift test` and `./Scripts/build-app.sh` — the build guard fails if the table
   didn't ship.

## Add / localize a string

1. Add the English line to `en.lproj/Localizable.strings` and a translation to each
   other `<lang>.lproj`.
2. Change the call site from `Text("…")` / `Button("…")` to `…(L10n.localized("…"))`.
   (Adding only the table entry does nothing — see "How it works".)

Interpolation uses printf specifiers: `Text("Version \(x)")` becomes the key
`"Version %@"` (use `%1$@`, `%2$lld`, … when arguments must reorder).

## Current scope

As of v1.25 "Fluent," coverage is broad: the onboarding chrome, the full menu
popover (`MenuRedesign.swift`), every Settings pane, the sleep-verdict copy
(`SleepOutlook`), notification templates (`Notifier`), the reason-engine
labels (`ReasonEngine`), and the human-readable CLI output (`--scan`,
`--status`, `--help`, etc. — **not** `--json` output, which is a machine
contract and stays in English by design). Remaining gaps: `Formatting.swift`'s
relative-time shorthand ("3m ago"), `Diagnostics.swift`'s report text, and a
few compound strings that stitch a localized template around an
un-localized fragment from a Model-layer type (`TriggerCondition.label` and
similar) — a smaller, well-scoped follow-up rather than the original
larger effort.

> **Translation quality note:** the German table was machine-translated (by an
> AI agent) in the v1.25 sweep — natural and grammatically checked, but it
> hasn't had a native-speaker pass. Treat it as a solid first draft; a
> native-German review is a genuinely useful, low-effort contribution.

> The tables are `.lproj/*.strings` rather than a `.xcstrings` String Catalog
> because the plain `swift build` used here (and in CI / `build-app.sh`) doesn't
> compile String Catalogs — only Xcode's build system does. `.strings` load
> everywhere the project builds. If Decaffeinate ever moves to an Xcode/`swiftbuild`
> build, migrating to a catalog is a drop-in.

## See it in another language

```sh
./Scripts/build-app.sh
open build/Decaffeinate.app --args -AppleLanguages '(de)'
```

The onboarding masthead should read **Willkommen**, with **Weiter** / **Loslegen**
buttons; About shows **Diagnose kopieren** and **Nach Updates suchen…**. (Or set
the app's language in System Settings → General → Language & Region → Applications.)
