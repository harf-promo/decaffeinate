# Design System & Harf Conformance

This document defines the Harf design-system contract for Decaffeinate, records
the macOS-specific deviations the app has deliberately sanctioned, inventories
residual conformance gaps in the live SwiftUI views, and sets out a bounded
implementation and test plan for the remaining uplift phases.

It is the canonical contract referenced by
[`Tests/DecaffeinateTests/HarfAdherenceTests.swift`](../Tests/DecaffeinateTests/HarfAdherenceTests.swift)
and
[`Sources/Decaffeinate/Views/WindowMetrics.swift`](../Sources/Decaffeinate/Views/WindowMetrics.swift).

> **Current conformance status: in progress, not complete.**
> Restoring `docs/DESIGN.md` repairs the missing documentation target cited by
> `HarfAdherenceTests.swift` and `WindowMetrics.swift`; it does not change
> product code or claim that the app already satisfies every Harf rule. Four of
> the five lexical gates in `HarfAdherenceTests` still carry non-zero violation
> ledgers (`12`, `28`, `4`, `9`), and additional un-gated deviations remain in
> `Sources/Decaffeinate/Views/` (see [§5](#5-residual-violation-inventory-actual-source-at-head)).

> **Historical phases note.**
> Only **Phase 0** (`3959689`, PR #14 — CI design, localization, and screenshot
> gates) and **Phase 1** (`cac95af`, PR #15 — six behavioral honesty fixes in
> `Sources/Decaffeinate/Core/`) were committed under numbered phase titles,
> followed by unnumbered PRs (#16, #18, #19, #20). **No historical planning
> document defining the original Phases 2–8 sequence exists in git history, pull
> requests, issues, or `docs/`.** Accordingly, the Phases 2–8 sequence in
> [§6](#6-new-proposed-phase-mapping-phases-2-8) is labeled as a **new proposed
> phase mapping** grounded in the current checkout rather than a reconstruction
> of an unrecorded historical plan.

---

## 1. Current Design Contract (Source-Cited)

### 1.1 Token Architecture & Single Source of Truth

| Layer | File | Role |
| --- | --- | --- |
| Brand & primitive tokens | [`Sources/Decaffeinate/Views/HarfTheme.swift`](../Sources/Decaffeinate/Views/HarfTheme.swift) | SwiftUI port of the Harf design foundation (`colors_and_type.css`): `Color` palette extensions, `Space`, `Radius`, `Metrics`, `HarfFont`, `View.eyebrow(_:)`, `View.scaledFont(_:weight:design:relativeTo:)`, `ScaledSystemFont`, `Hairline`, `DecaffeinateMark`, `HarfButtonStyle`, and `HarfPill`. |
| Surface skin (`@Environment(\.theme)`) | [`Sources/Decaffeinate/Views/Theme.swift`](../Sources/Decaffeinate/Views/Theme.swift) | `Theme.nightcap` — binds surface, hairline, ink, accent, and teal slots to `HarfTheme` `Color` tokens so light/dark appearances share one palette, alongside popover and card layout metrics. |
| Window & capture frames | [`Sources/Decaffeinate/Views/WindowMetrics.swift`](../Sources/Decaffeinate/Views/WindowMetrics.swift) | Single declaration of app-drawn window dimensions read by both live views and [`ScreenshotRenderer`](../Sources/Decaffeinate/Views/ScreenshotRenderer.swift). |
| Brand mark geometry | [`Sources/Decaffeinate/Core/BrandMark.swift`](../Sources/Decaffeinate/Core/BrandMark.swift) | Single y-down `CGPath` source (`BrandMark.logo(in:)`, `BrandMark.menuGlyph(for:in:)`) shared by `DecaffeinateMark` (in-app `Canvas`), [`MugIcon`](../Sources/Decaffeinate/Core/MugIcon.swift) (18 pt menu-bar template images), and [`IconRenderer`](../Sources/Decaffeinate/Views/IconRenderer.swift) (`icon-1024.png`, `AppIcon.icns`, `decaffeinate-mark.svg`). |

### 1.2 Color, Surface, Hairline & Status Rules

Defined in `Sources/Decaffeinate/Views/HarfTheme.swift:12-85`:

1. **Green is punctuation (`< 5%` of a surface), never a UI status state**
   (`HarfTheme.swift:13`). At most one brand-green mark should anchor a surface.
2. **Active or healthy UI state uses `Color.positive` (teal), not brand green**
   (`HarfTheme.swift:14`, `Theme.swift:65`, `MenuRedesign.swift:825`,
   `SleepTone.color(_:)` at `MenuRedesign.swift:1066-1071`).
3. **Brand tokens never flip between light and dark appearances**
   (`HarfTheme.swift:15, 40-51`), whereas ink, paper, and hairline tokens resolve
   dynamically via `NSColor(name: nil)` appearance matching (`.aqua` vs
   `.darkAqua`, `HarfTheme.swift:32-38`, mirroring CSS `light-dark()`).
4. **Foreground contrast on brand green is fixed**:
   - `Color.onGreen` (`0x1A1B1D`, `grey-900`) is the **only** legal foreground
     on a green fill (`HarfTheme.swift:49-50, 302, 349`; `MenuRedesign.swift:1135`).
   - `Color.accentText` (`0x3D5A14`, `green-900`) is the **only** green token
     legible as text on light paper (`HarfTheme.swift:47-48`).

| Family | Token (`Color.*`) | Light / Fixed sRGB | Dark sRGB | Notes (`HarfTheme.swift`) |
| --- | --- | --- | --- | --- |
| Brand | `harfGrey` | `0x939598` | *(fixed)* | Brand neutral (`:41`) |
| Brand | `harfGreen` | `0x7EAE3C` | *(fixed)* | Current sage-lime; `#A4CD39` decision open ([§2](#2-unresolved-brand-green-decision-a4cd39-vs-7eae3c)) (`:42-44`) |
| Brand | `greenHover` / `greenPress` | `0x6F9B32` / `0x5A8228` | *(fixed)* | Hover and `:active` press states (`:45-46`) |
| Brand | `accentText` / `onGreen` | `0x3D5A14` / `0x1A1B1D` | *(fixed)* | Green text on light paper; ink on green fill (`:48-50`) |
| Ink | `ink1` | `0x1A1B1D` | `0xF2F2F3` | Primary text and primary Harf button fill (`:53`) |
| Ink | `ink2` | `0x4A4B4E` | `0xBBBBBE` | Secondary body copy (`:54`) |
| Ink | `ink3` | `0x646669` | `0x939598` | Metadata/captions — WCAG AA on every paper surface (`:55`) |
| Ink | `ink4` | `0x939598` | `0x6E7073` | Muted chrome, chevrons, inactive step numerals (`:56`) |
| Ink | `inkDisabled` / `grey800` | `0x4A4B4E` / `0x2A2B2D` | `0x939598` / *(fixed)* | Disabled label (`:57`); primary button hover (`:58`) |
| Surface | `paper` | `0xFFFFFF` | `0x0F1011` | Base window/popover ground (`:61`) |
| Surface | `paper2` | `0xFAFAFA` | `0x16181A` | Raised card, sidebar, and detail ground (`:62`) |
| Surface | `paper3` | `0xF2F2F3` | `0x1D1F22` | Active/pending card and disabled button fill (`:63`) |
| Surface | `paper4` | `0xEAEAEC` | `0x25282B` | Highest stepped neutral surface (`:64`) |
| Hairline | `rule` | `0xE4E4E6` | `0x2A2D31` | Standard 1 pt structural divider (`Hairline`, `:67, 193-196`) |
| Hairline | `rule2` | `0x9C9EA1` | `0x3E4146` | Control boundary — passes WCAG 1.4.11 (`:68`) |
| Hairline | `ruleStrong` | `0x1A1B1D` | `0xFFFFFF` | High-contrast emphasis rule (`:69`) |
| Status | `positive` / `*Tint` / `*Deep` | `0x2F8C5A` / `0xDCEFE3` / `0x175A37` | *(fixed)* | Teal active/healthy state & stamped pill (`:73-75`) |
| Status | `warning` / `*Tint` / `*Deep` | `0xD49A2A` / `0xF8EED0` / `0x8C6310` | *(fixed)* | Amber caution & genuine sleep-blocked alert (`:76-78`) |
| Status | `critical` / `*Tint` / `*Deep` | `0xC7432B` / `0xF5D9D2` / `0x82230F` | *(fixed)* | Destructive action, thermal/battery guard, error (`:79-81`) |
| Status | `info` / `*Tint` / `*Deep` | `0x3E78A8` / `0xDEEAF2` / `0x1B4368` | *(fixed)* | Informational chip & Sparkle check state (`:82-84`) |

### 1.3 Spacing Ladder

`enum Space` (`HarfTheme.swift:100-110`) defines the nine-step spacing scale in
points:

`4 (s1) · 8 (s2) · 12 (s3) · 16 (s4) · 24 (s5) · 32 (s6) · 48 (s7) · 64 (s8) · 96 (s9)`

Shared component geometry that crosses views lives in `enum Metrics`
(`Metrics.rowIcon = 26`, `HarfTheme.swift:126-129`), and canonical window/capture
frames live in `enum WindowMetrics` (`WindowMetrics.swift:15-35`).

### 1.4 Shape, Corner Radii & Elevation

The Harf structural grammar (`HarfTheme.swift:10, 113-123, 192-196` and
`HarfAdherenceTests.swift:22-25, 44-66`) enforces three rules:

1. **Circular corners, never superellipses.** Harf containers must not pass
   `style: .continuous` (`HarfAdherenceTests.testNoContinuousCornerStyleOutsideTheAppIconMask`,
   `HarfAdherenceTests.swift:49-54`).
2. **Harf radius set (`{0, 2, 4, pill}`).** Harf ships `--r-0/1/2/pill`
   (`0`, `2`, `4`, `999` pt; `HarfAdherenceTests.swift:22, 44`).
   *Current code gap:* `enum Radius` (`HarfTheme.swift:115-123`) defines
   `sharp = 0`, `soft = 4`, `control = 8`, `card = 10`, and `pill = 999`. Both
   `control` (`8`) and `card` (`10`) were introduced for Nightcap soft cards and
   sit outside `{0, 2, 4, pill}`, while `2` has no named `Radius` constant yet
   (see [§5.3](#53-scanner-blind-spots-and-un-gated-residual-deviations)).
3. **1 pt hairlines, never resting shadows.** Surface separation uses `Hairline`
   (`Rectangle().fill(color).frame(height: 1)`, `HarfTheme.swift:193-196`) and
   1 pt `.stroke(...)` borders. Resting `.shadow(` modifiers are prohibited
   outside the single floating-panel exception (`HarfAdherenceTests.swift:61-66`).

### 1.5 Typography & Dynamic Type

- **Typeface:** SF Pro (`Font.system`), with `.monospaced` for code and step
  numerals (`HarfTheme.swift:132-148`).
- **5/4 modular type ladder:** `HarfAdherenceTests.typeLadder`
  (`HarfAdherenceTests.swift:35-37`) permits only integer point sizes on
  `16 × 1.25^n` (rounded) plus the named `12` pt half-rung:
  `{10, 12, 13, 16, 20, 25, 31, 39, 49, 61, 76, 95, 119, 149, 186, 233}`.
- **Tracked uppercase label voice:** `View.eyebrow(_:)` applies `HarfFont.eyebrow`
  (`10` pt semibold), `.textCase(.uppercase)`, and `.tracking(1.1)`
  (`HarfTheme.swift:152-157`); `HarfPill` uses `HarfFont.eyebrow`, `.uppercase`,
  and `.tracking(0.7)` (`HarfTheme.swift:327-339`).
- **Dynamic Type scaling:** Resizable and scrollable surfaces use
  `View.scaledFont(_:weight:design:relativeTo:)` (`ScaledSystemFont` backed by
  `@ScaledMetric`, `HarfTheme.swift:163-190`) so design sizes scale with user
  accessibility preferences while preserving the base ladder size.
  *Current code gap:* five `HarfFont` constants (`display = 30`, `title = 15`,
  `lede = 15`, `micro = 11`, `codeSmall = 11` at `HarfTheme.swift:137-147`) and
  `HarfButtonStyle.Size.large` (`14` at `HarfTheme.swift:276`) are themselves off
  `typeLadder` and are counted in `Ledger.offLadderFontSize` ([§5.2](#52-line-by-line-lexical-hit-inventory)).

### 1.6 Motion & Reduce Motion

- **×2 duration ladder:** `HarfAdherenceTests.motionLadder`
  (`HarfAdherenceTests.swift:40, 88-93`) permits only
  `{0.05, 0.1, 0.2, 0.4, 0.8}` seconds (`50 / 100 / 200 / 400 / 800 ms`).
- **Reduce Motion gating:** Motion is allowed, not banned, but every view
  animation or transition must honor `@Environment(\.accessibilityReduceMotion)`
  through a shared wrapper rather than invoking raw `.animation(`,
  `withAnimation(`, or `.transition(` directly in view files
  (`HarfAdherenceTests.swift:95-106`).

---

## 2. Unresolved Brand-Green Decision: `#A4CD39` vs `#7EAE3C`

> **Status: OPEN OWNER / DESIGN DECISION — explicitly preserved.**
> Neither this document nor a mechanical conformance pass should silently revert
> `#7EAE3C` to `#A4CD39` or erase `#A4CD39` as the upstream Harf token without an
> explicit decision.

### Context in Source & History

- **Canonical Harf brand lime (`#A4CD39`):** When `HarfTheme.swift` was introduced
  in `ab1d7b7` (*"Harf design foundation (Part A): SwiftUI token layer"*), brand
  green matched upstream `colors_and_type.css` at `#A4CD39` (`BrandMark.Ink.moon`
  carried `#A4CD39` through `v1.26.0`).
- **v1.26.1 darkening (`#7EAE3C`):** Commit `a4c5c03` (`v1.26.1`,
  [`CHANGELOG.md`](../CHANGELOG.md) lines 108–109) deepened `Color.harfGreen` to
  sage-lime `0x7EAE3C` (`HarfTheme.swift:42-44`), paired with `greenHover = 0x6F9B32`
  (`:45`), `greenPress = 0x5A8228` (`:46`), `IconRenderer.moonColor` /
  `svgHex(.moon) = "#7EAE3C"` (`IconRenderer.swift:15-16, 38`), and regenerated
  icon assets (`assets/icon-1024.png`, `assets/AppIcon.icns`,
  `assets/decaffeinate-mark.svg`). The inline comment (`HarfTheme.swift:42-43`)
  records the reason: *"the old `#A4CD39` read as highlighter on Sleep Now and
  washed out the moon."*

### Why the Decision Remains Coupled to Button Hierarchy

The glare that prompted `#A4CD39` → `#7EAE3C` came primarily from `RDPrimaryButton`
(`MenuRedesign.swift:151, 870, 999, 1126-1128` and
`ClamshellAssistantView.swift:153`) painting the entire resting background of
full-width primary buttons (`Sleep Now`, `Arm clamshell session`) in
`theme.accent` (`Color.harfGreen`). That departs from `HarfTheme.swift:13, 228-230, 291`,
where `HarfButtonStyle` `.primary` uses `Color.ink1` at rest (`grey800` on hover)
and reserves green strictly for `:active` press (`greenPress`) and `< 5%` brand
punctuation:

- **Option A — Strict Harf token & hierarchy parity:** Restore `Color.harfGreen`
  to `#A4CD39` (`0xA4CD39`) *together with* moving primary resting button fills
  back to `Color.ink1` (`HarfButtonStyle(variant: .primary)`), keeping `#A4CD39`
  solely on `< 5%` punctuation (the crescent moon in `DecaffeinateMark` /
  `IconRenderer`, onboarding 5 pt bullets, and `:active` press feedback).
  Requires re-verifying moon contrast on light paper (`#FFFFFF`) and regenerating
  `assets/` via `Decaffeinate --icon assets`.
- **Option B — Sanctioned Decaffeinate sage-lime (`#7EAE3C`):** Keep
  `0x7EAE3C` (`greenHover` `0x6F9B32`, `greenPress` `0x5A8228`) as a documented
  app-level deviation from upstream `#A4CD39` tuned for macOS menu-bar legibility
  on light paper, and separately decide whether `RDPrimaryButton` keeps a green
  fill or adopts `Color.ink1`.

Until the owner selects Option A or Option B (scheduled as the Phase 6 decision
gate in [§6](#6-new-proposed-phase-mapping-phases-2-8)), `0x7EAE3C` remains in
code and `#A4CD39` remains recorded here as the unresolved upstream baseline.

---

## 3. Sanctioned Exceptions and Exemption Protocol

The following deviations from raw Harf web defaults are **deliberately sanctioned**
for macOS fidelity and accessibility:

| Exception | File & Lines | Gate Treatment | Structural Rationale |
| --- | --- | --- | --- |
| Third-party macOS app-icon mask | [`Sources/Decaffeinate/Views/AppIconProvider.swift`](../Sources/Decaffeinate/Views/AppIconProvider.swift) (`AppIconProvider.swift:65`, plus proportional fallback glyph `AppIconProvider.swift:68`) | `skippingFiles: ["AppIconProvider.swift"]` in `testNoContinuousCornerStyleOutsideTheAppIconMask` (`HarfAdherenceTests.swift:50-52`) | `AppIconView` renders *other* macOS applications' bundle icons in blocker rows clipped to `size * 0.22` with `style: .continuous` — Apple's standard app-icon superellipse, not a Harf container. (`IconRenderer.swift:105-108` likewise clips Decaffeinate's own `.icns` master at `s * 0.2237`.) |
| Floating pre-sleep HUD elevation shadow | [`Sources/Decaffeinate/Views/SleepWarningHUD.swift`](../Sources/Decaffeinate/Views/SleepWarningHUD.swift) (`SleepWarningHUD.swift:53`, hosted by `SleepWarningPresenter` at `SleepWarningHUD.swift:109-120`) | `skippingFiles: ["SleepWarningHUD.swift"]` in `testNoRestingShadowsOutsideTheFloatingPanel` **only** (`HarfAdherenceTests.swift:61-65`) | `SleepWarningHUD` renders inside a borderless, non-activating floating `NSPanel` (`hasShadow = false`) over arbitrary user windows/wallpapers where a 1 pt hairline cannot guarantee an edge. `SleepWarningHUD.swift` is **not** exempt from the corner-style, font-ladder, or motion gates. |
| OS-owned chrome & canonical window sizes | [`Sources/Decaffeinate/Views/WindowMetrics.swift`](../Sources/Decaffeinate/Views/WindowMetrics.swift) (`WindowMetrics.swift:15-35`), `MenuRedesign.swift:56-65`, `SleepWarningHUD.swift:128-134` | Outside `Space` token checks | macOS menu-bar height, `NSScreen.visibleFrame` popover height clamping (`0.8` / `0.92`), safe areas, and fixed window/capture frames (`700×520`, `500×440`, `360` pt utility panels) are host-OS facts shared once between live views and `ScreenshotRenderer`. |
| Dynamic Type `@ScaledMetric` scaling | `HarfTheme.swift:159-190` (`View.scaledFont`, `ScaledSystemFont`) | Base literal checked against `typeLadder` (`HarfAdherenceTests.swift:75-83`) | Harf specifies fixed CSS sizes; macOS accessibility requires explanatory and menu copy to scale with user text-size settings via `@ScaledMetric` anchored to a ladder point size. |
| Headless `CGColor` / SVG palette constants | [`Sources/Decaffeinate/Views/IconRenderer.swift`](../Sources/Decaffeinate/Views/IconRenderer.swift) (`IconRenderer.swift:8-43`) | Must match `HarfTheme.swift` hexes | `Decaffeinate --icon <dir>` runs without SwiftUI; `IconRenderer` mirrors the brand hexes in `CGColor` and SVG strings so asset generation stays headless. |

### Protocol for Adding a Sanctioned Exception

Per `HarfAdherenceTests.assertLedger` (`HarfAdherenceTests.swift:136-141`), a new
exception is valid **only** when the same PR:

1. Documents the file, symbol, and macOS/accessibility reason in the table above;
2. Scopes `skippingFiles` in `HarfAdherenceTests.swift` to that single test
   method (never globally in `SourceScanner`); and
3. Decrements that rule's `Ledger` constant if existing counted hits lived in the
   newly exempted file.

---

## 4. Lexical Gates & `SourceScanner` Mechanics

[`Tests/DecaffeinateTests/SourceScanner.swift`](../Tests/DecaffeinateTests/SourceScanner.swift)
and
[`Tests/DecaffeinateTests/HarfAdherenceTests.swift`](../Tests/DecaffeinateTests/HarfAdherenceTests.swift)
enforce design conformance by reading source files under
`Sources/Decaffeinate/Views` as UTF-8 text:

- **Comment filtering (`SourceScanner.swift:78-80`):** Lines whose trimmed text
  starts with `//`, `///`, or `*` are skipped so comments explaining a banned
  value do not trip the gate.
- **Whole-line numeric literal tokenization (`SourceScanner.swift:95-136`):**
  `numberLiterals(in:)` extracts every standalone numeric literal on a line while
  ignoring digits attached to identifiers (`s1`, `paper2`, `grey800`).
  `integerLiterals(in:)` filters to whole numbers (`v == v.rounded()`), so a
  proportional expression such as `size * 0.66` (`AppIconProvider.swift:68`)
  produces no integer size literal.
- **Label-scoped duration parsing (`HarfAdherenceTests.swift:115-125`):**
  `durations(in:)` reads only the numeric token immediately following each
  `duration:` label on a line, avoiding false positives on unrelated integers on
  the same line (such as `withAnimation(.easeInOut(duration: 0.2)) { page += 1 }`
  at `OnboardingView.swift:94`).
- **Exact-equality ledgers (`HarfAdherenceTests.swift:12-32, 127-144`):**
  `assertLedger` asserts `hits.count == expected` (not `<=`). Introducing a new
  violation fails with *"grew"*; fixing violations without decrementing `Ledger`
  in the same commit fails with *"shrank"*. Once a ledger reaches `0`, it remains
  at `0`.
- **Companion CI gates:**
  - [`Tests/DecaffeinateTests/LocalizationTests.swift`](../Tests/DecaffeinateTests/LocalizationTests.swift)
    (`LocalizationTests.swift:256-323`) and [`Scripts/check-l10n.sh`](../Scripts/check-l10n.sh) enforce
    `.lproj` key parity and `SourceScanner.localizedKeys()` coverage
    (`untabledKeyLedger = 0`).
  - [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) (`ci.yml:64-74`) runs
    `swift run Decaffeinate --screenshots "$RUNNER_TEMP/screenshots"` and uploads
    the 30 rendered light/dark PNGs as a build artifact, failing non-zero on any
    missing or failed write (`ScreenshotRenderer.swift:11-20, 210-221`).

---

## 5. Residual Violation Inventory (Actual Source at `HEAD`)

> **Labeling convention (test ledger vs static source scan vs executed tests).**
> - **Declared Test Ledger Value:** the integer constant hardcoded in
>   `Tests/DecaffeinateTests/HarfAdherenceTests.swift:21-32` (or
>   `LocalizationTests.swift:263`).
> - **Static Source-Scan Count:** the number of matching lines counted directly
>   from `Sources/Decaffeinate/Views/*.swift` in this checkout (`HEAD` `bb89176`)
>   by applying the exact predicates in `SourceScanner.swift` and
>   `HarfAdherenceTests.swift`.
> - **Executed XCTest / Render Status:** `swift build`, `swift test`, `swift run`,
>   and `Scripts/*.sh` were **not invoked locally** in this docs-only pass; live
>   test execution and screenshot rendering run in GitHub Actions CI (`ci.yml`).

### 5.1 Gate Summary: Declared Test Ledgers vs Static Source-Scan Counts

| Gate (`HarfAdherenceTests` / `LocalizationTests`) | Predicate (`under: "Views"`) | Exempt Files (`skippingFiles`) | Declared Test Ledger | Static Source-Scan Count | Exempt Hits in Skipped Files |
| --- | --- | --- | ---: | ---: | ---: |
| `testNoContinuousCornerStyleOutsideTheAppIconMask` | `line.contains("style: .continuous")` | `AppIconProvider.swift` | `12` (`Ledger.continuousCornerStyle`) | `12` | `1` (`AppIconProvider.swift:65`) |
| `testNoRestingShadowsOutsideTheFloatingPanel` | `line.contains(".shadow(")` | `SleepWarningHUD.swift` | `0` (`Ledger.restingShadow`) | `0` | `1` (`SleepWarningHUD.swift:53`) |
| `testEveryFontSizeIsOnTheTypeLadder` | `(scaledFont( \|\| system(size:))` with integer literal `∉ typeLadder` | *(none)* | `28` (`Ledger.offLadderFontSize`) | `28` | `0` |
| `testEveryAnimationDurationIsOnTheMotionLadder` | `durations(in: line)` value `∉ {0.05, 0.1, 0.2, 0.4, 0.8}` | *(none)* | `4` (`Ledger.offLadderDuration`) | `4` | `0` |
| `testEveryAnimationIsGatedOnReduceMotion` | `.animation(` \|\| `withAnimation(` \|\| `.transition(` | *(none)* | `9` (`Ledger.ungatedMotion`) | `9` | `0` |
| `LocalizationTests.testEveryLiteralKeyExistsInTheEnglishTable` | `SourceScanner.localizedKeys()` absent from `en.lproj` | *(scans all `Sources/Decaffeinate`)* | `0` (`untabledKeyLedger`, decremented `5 → 0` in PR #19) | `0` | — |

### 5.2 Line-by-Line Lexical Hit Inventory

#### A. Squircle Corner Style (`style: .continuous`) — 12 Static Source Hits (Ledger: `12`)

- `Views/MenuRedesign.swift:280` — `autoSleepRow` card background (`Radius.control`)
- `Views/MenuRedesign.swift:452` — `explainerCard` background (`Radius.control`)
- `Views/MenuRedesign.swift:455` — `explainerCard` stroke overlay (`Radius.control`)
- `Views/MenuRedesign.swift:479` — `verdictBanner` background (`Radius.control`)
- `Views/MenuRedesign.swift:661` — `RDRow` clip shape (`theme.cardRadius`)
- `Views/MenuRedesign.swift:938` — `RDRow.rowBackground` fill (`theme.cardRadius`)
- `Views/MenuRedesign.swift:949` — `RDRow.cardBorder` stroke (`theme.cardRadius`)
- `Views/MenuRedesign.swift:1111` — `RDButtonBody` background (`Radius.control`)
- `Views/MenuRedesign.swift:1113` — `RDButtonBody` stroke overlay (`Radius.control`)
- `Views/SettingsView.swift:68` — `sidebarRow` selection background (`Radius.control`)
- `Views/SleepWarningHUD.swift:47` — HUD panel background (`Radius.card`)
- `Views/SleepWarningHUD.swift:50` — HUD panel border stroke (`Radius.card`)

*(Sanctioned exempt site not in count: `Views/AppIconProvider.swift:65`.)*

#### B. Resting Shadows (`.shadow(`) — 0 Static Source Hits (Ledger: `0`)

Zero non-exempt hits. *(Sanctioned exempt site not in count:
`Views/SleepWarningHUD.swift:53`.)*

#### C. Off-Ladder Font Sizes (`∉ {10, 12, 13, 16, 20, 25, 31, …}`) — 28 Static Source Hits (Ledger: `28`)

Grouped by off-ladder integer point size:

- **`9` pt (2 hits — nearest ladder rung: `10`):**
  - `Views/Components.swift:137` (`AssertionDetailView.technicalToggle` disclosure chevron)
  - `Views/MenuRedesign.swift:559` (`RDList.othersDisclosure` chevron)
- **`11` pt (11 hits — nearest ladder rungs: `10` or `12`):**
  - `Views/ClamshellAssistantView.swift:196` (`screensOffFallback` footnote)
  - `Views/ClamshellAssistantView.swift:210` (`foreignSleepDisabledNote`)
  - `Views/Components.swift:18` (`Chip` label)
  - `Views/HarfTheme.swift:144` (`HarfFont.micro`)
  - `Views/HarfTheme.swift:147` (`HarfFont.codeSmall`)
  - `Views/MenuRedesign.swift:216` (`RDActionBar` `lastError` line)
  - `Views/MenuRedesign.swift:467` (`verdictBanner` SF Symbol glyph)
  - `Views/MenuRedesign.swift:565` (`othersDisclosure` count badge)
  - `Views/MenuRedesign.swift:686` (`RDRow` verdict glyph)
  - `Views/MenuRedesign.swift:983` (`RDFooter` restart hint)
  - `Views/MenuRedesign.swift:1009` (`RDFooter` `"Slept …"` label)
- **`14` pt (5 hits — nearest ladder rungs: `13` or `16`; see also multiline blind spot in §5.3):**
  - `Views/HarfTheme.swift:276` (`HarfButtonBody.font` `.large` size)
  - `Views/MenuRedesign.swift:585` (`RDList.emptyState` copy)
  - `Views/MenuRedesign.swift:673` (`RDRow` blocker title)
  - `Views/OnboardingView.swift:46` (`OnboardingView` masthead `"Decaffeinate"` wordmark)
  - `Views/SleepWarningHUD.swift:28` (`"Sleeping in %ds"` headline)
- **`15` pt (6 hits — nearest ladder rung: `16`):**
  - `Views/HarfTheme.swift:139` (`HarfFont.title`)
  - `Views/HarfTheme.swift:140` (`HarfFont.lede`)
  - `Views/MenuRedesign.swift:636` (`RDRow.rowIcon` unattributed audio symbol)
  - `Views/OnboardingView.swift:186` (`OnboardingPanelContent` body)
  - `Views/OnboardingView.swift:228` (`NotificationChoicePanel` body)
  - `Views/SettingsView.swift:946` (`AboutView` tagline)
- **`30` pt (3 hits — nearest ladder rung: `31`):**
  - `Views/HarfTheme.swift:137` (`HarfFont.display`)
  - `Views/OnboardingView.swift:181` (`OnboardingPanelContent` hero heading)
  - `Views/OnboardingView.swift:223` (`NotificationChoicePanel` hero heading)
- **Additional `11` pt non-scaled system font in Settings sidebar (1 hit — `2 + 11 + 5 + 6 + 3 + 1 = 28` total):**
  - `Views/SettingsView.swift:48` (`sidebarLabel` `.font(.system(size: 11, weight: .semibold))`)

#### D. Off-Ladder Animation Durations (`∉ {0.05, 0.1, 0.2, 0.4, 0.8}`) — 4 Static Source Hits (Ledger: `4`)

All four hits use `duration: 0.15` (`150 ms`, between the `0.1` and `0.2` rungs):

- `Views/MenuRedesign.swift:423` — `withAnimation(.easeInOut(duration: 0.15)) { showExplainer.toggle() }`
- `Views/MenuRedesign.swift:509` — `withAnimation(.easeInOut(duration: 0.15)) { showAllHolders = true }`
- `Views/MenuRedesign.swift:555` — `withAnimation(.easeInOut(duration: 0.15)) { showOthers.toggle() }`
- `Views/MenuRedesign.swift:719` — `if !pending { withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() } }`

#### E. Motion Not Gated on Reduce Motion — 9 Static Source Hits (Ledger: `9`)

Zero files under `Sources/Decaffeinate/Views/` currently read
`@Environment(\.accessibilityReduceMotion)`:

- `Views/HarfTheme.swift:265` — `.animation(.easeOut(duration: 0.1), value: hovering)`
- `Views/HarfTheme.swift:266` — `.animation(.easeOut(duration: 0.05), value: configuration.isPressed)`
- `Views/MenuRedesign.swift:423` — `withAnimation(.easeInOut(duration: 0.15))` (`showExplainer`)
- `Views/MenuRedesign.swift:509` — `withAnimation(.easeInOut(duration: 0.15))` (`showAllHolders`)
- `Views/MenuRedesign.swift:555` — `withAnimation(.easeInOut(duration: 0.15))` (`showOthers`)
- `Views/MenuRedesign.swift:719` — `withAnimation(.easeInOut(duration: 0.15))` (`showDetails`)
- `Views/MenuRedesign.swift:1118` — `.animation(.easeOut(duration: 0.1), value: hovering)` (`RDButtonBody`)
- `Views/OnboardingView.swift:68` — `.transition(.asymmetric(...))` (onboarding page slide/fade)
- `Views/OnboardingView.swift:94` — `withAnimation(.easeInOut(duration: 0.2)) { page += 1 }`

### 5.3 Scanner Blind Spots and Un-Gated Residual Deviations

Direct reading of `Sources/Decaffeinate/Views/*.swift` surfaces seven residual
categories that the five lexical predicates in `HarfAdherenceTests` do **not**
currently catch:

1. **Multiline `scaledFont(` call escapes `testEveryFontSizeIsOnTheTypeLadder`:**
   `Views/MenuRedesign.swift:1104-1106` formats `RDButtonBody`'s font modifier
   across three lines (`.scaledFont(\n compact ? 12 : 14, ...)`). Because
   `HarfAdherenceTests.swift:76-81` checks `line.contains("scaledFont(")` and
   `integerLiterals(in: line)` on the **same line**, line 1104 has no integer
   literals and line 1105 lacks `scaledFont(`, so the off-ladder `14` escapes
   the 28-hit ledger — despite `HarfAdherenceTests.swift:72-74` naming
   `compact ? 12 : 14` as its motivating case.
2. **Indirect font-size property escapes `testEveryFontSizeIsOnTheTypeLadder`:**
   `Theme.nightcap` sets `headlineSize: 17` (`Views/Theme.swift:72`, off-ladder
   between `16` and `20`), consumed indirectly via `.system(size: headlineSize, ...)`
   (`Views/Theme.swift:42`) and `.scaledFont(theme.headlineSize, ...)`
   (`Views/MenuRedesign.swift:83`).
3. **Un-tokenized SwiftUI semantic font modifiers (`16` definitions across 2 files):**
   `Views/MenuRedesign.swift:320, 334, 354` and
   `Views/SettingsView.swift:154, 187, 428, 438, 446, 550, 766, 853, 862, 885, 901, 971`
   (plus the shared `View.settingsCaption()` helper at `Views/SettingsView.swift:1112-1114`)
   call `.font(.caption)` or `.font(.caption2)`, bypassing both `HarfFont` and
   `scaledFont`.
4. **System `.secondary` foregrounds bypassing `Color.ink*` (`4` sites):**
   `Views/SettingsView.swift:446, 550, 800, 1113` use `.foregroundStyle(.secondary)`
   instead of `Color.ink3` / `Color.ink4`.
5. **Off-contract `Radius` tokens and raw corner literal:**
   `Radius.control = 8` and `Radius.card = 10` (`Views/HarfTheme.swift:119-121`,
   also used without `.continuous` at `Views/HarfTheme.swift:259, 262`) exceed
   Harf's `{0, 2, 4, pill}` radius set (`HarfAdherenceTests.swift:44`), and
   `Views/MenuRedesign.swift:957` passes a raw `RoundedRectangle(cornerRadius: 2)`
   literal with no `Radius` token.
6. **Brand-green surface budget & dark-mode `Color.accentText` contrast:**
   - `RDPrimaryButton` (`Views/MenuRedesign.swift:151, 870, 999, 1126-1128`;
     `Views/ClamshellAssistantView.swift:153`) uses `Color.harfGreen` as a full
     resting button fill rather than `HarfButtonStyle`'s `Color.ink1` primary
     fill ([§2](#2-unresolved-brand-green-decision-a4cd39-vs-7eae3c)).
   - `Views/SleepWarningHUD.swift:24, 40` places both a `Color.harfGreen` symbol
     and a `.accent` (`Color.harfGreen`) button on the same 360 pt card (two
     green marks on one surface).
   - `Views/SettingsView.swift:60, 63, 69` styles the selected sidebar row with
     fixed `Color.accentText` (`0x3D5A14`) on `Color.harfGreen.opacity(0.18)`
     over `theme.card` (`0x16181A` in dark mode). `0x3D5A14` is tuned for light
     paper (`HarfTheme.swift:47`) and has low contrast on dark `paper2`.
7. **Un-laddered spacing/padding literals and adjacent Phase 0 tick debt:**
   - `Views/Theme.swift:70-71` (`rowGap: 6`, `contentInset: 14`),
     `Views/HarfTheme.swift:282-284` (`padV` `6 / 9 / 11`),
     `Views/MenuRedesign.swift:1109` (`6 : 9`), `Views/SettingsView.swift:66`
     (`padding(.vertical, 7)`), `Views/SettingsView.swift:926` (`padding(8)` raw
     literal instead of `Space.s2`), and `1–3` pt optical nudges are not checked
     by a spacing gate.
   - Outside `Views/`, the non-visual uplift item retracted in Phase 0 (`3959689`
     / PR #14) remains open: `ProcessProvenanceResolver` still executes inside
     the 1 Hz `AppState.tick()` across six call sites
     ([`docs/ARCHITECTURE.md`](ARCHITECTURE.md) lines 82–88;
     [`Sources/Decaffeinate/Core/ProcessProvenanceResolver.swift`](../Sources/Decaffeinate/Core/ProcessProvenanceResolver.swift)
     lines 34–38).

---

## 6. New Proposed Phase Mapping (Phases 2-8)

*Label: **New Proposed Phase Mapping** — the historical Phases 2–8 planning
artifact is unavailable in the repository. Phase 0 (`3959689`, PR #14) and
Phase 1 (`cac95af`, PR #15) are already merged on `main`, alongside unnumbered
PRs #16 (preview PNGs), #18 (`SleepSimulator`), #19 (`L10n` completion,
`untabledKeyLedger` `5 → 0`), and #20 (`ViewThatFits` popover overflow fix).*

Each phase below is bounded to a coherent diff so its ledger delta and visual
impact can be reviewed independently on macOS with `swift build && swift test`,
`swift format lint --strict --recursive --configuration .swift-format Sources Tests Package.swift`,
and `swift run Decaffeinate --screenshots <dir>` (see [`docs/PREVIEW.md`](PREVIEW.md)).

### Phase 2 — Scanner Hardening (Close Lexical Blind Spots, Zero UI Change)

- **Scope:** Extend `SourceScanner` (`Tests/DecaffeinateTests/SourceScanner.swift`)
  with statement/call-span scanning for `scaledFont(...)` and `system(size:...)`
  across line breaks so wrapped calls like `MenuRedesign.swift:1104-1106` are
  inspected in full. Add `HarfAdherenceTests` checks (seeded at exact current
  counts, with zero product diff) for indirect `*Size:` font constants in
  `Theme.swift`, raw SwiftUI semantic `.font(.caption...)` calls, and raw
  `.foregroundStyle(.secondary)` calls in `Sources/Decaffeinate/Views`.
- **Ledger transition:** `offLadderFontSize` re-seeded `28 → 30` (capturing
  `MenuRedesign.swift:1105` `14` and `Theme.swift:72` `17`); new exact-equality
  ledgers seeded for semantic SwiftUI fonts (`16`) and `.secondary` foregrounds
  (`4`).
- **Tests:** Unit tests on `SourceScanner` proving multiline `scaledFont(\n compact ? 12 : 14)`
  and `headlineSize: 17` fail if un-ledgered; `swift test` green.

### Phase 3 — Motion Ladder & Reduce-Motion Gate (`offLadderDuration` & `ungatedMotion` → `0`)

- **Scope:** Introduce a dedicated motion-primitives wrapper file under
  `Sources/Decaffeinate/Views/` defining named ×2 duration tokens
  (`50 / 100 / 200 / 400 / 800 ms`) and Reduce-Motion-aware helpers (view
  animation, imperative animation, and accessibility-gated page transition
  modifiers reading `@Environment(\.accessibilityReduceMotion)`). Snap the four
  `0.15` s menu disclosures (`MenuRedesign.swift:423, 509, 555, 719`) onto
  `0.1` s or `0.2` s, and migrate all nine animation/transition call sites
  (`HarfTheme.swift:265-266`, `MenuRedesign.swift:423, 509, 555, 719, 1118`,
  `OnboardingView.swift:68, 94`).
- **Scanner interaction:** Because `testEveryAnimationIsGatedOnReduceMotion`
  matches raw `.animation(`, `withAnimation(`, and `.transition(` across `Views`,
  register that single motion-primitives wrapper file in that test's
  `skippingFiles` and add it to
  [§3](#3-sanctioned-exceptions-and-exemption-protocol) as the sole sanctioned
  primitive wrapper.
- **Ledger transition:** `Ledger.offLadderDuration: 4 → 0`;
  `Ledger.ungatedMotion: 9 → 0`.
- **Tests:** Unit test verifying the Reduce-Motion wrapper suppresses
  non-essential motion when Reduce Motion is enabled; `swift test` and
  `--preview` check.

### Phase 4 — Type Ladder & Semantic Ink Alignment (`offLadderFontSize` → `0`)

- **Scope:** Snap `HarfFont` tokens (`HarfTheme.swift:136-148`) and
  `HarfButtonStyle.Size.large` (`HarfTheme.swift:276`) onto `typeLadder`
  (`30 → 31`, `15 → 16`, `14 → 13` or `16`, `11 → 10` or `12`), snap
  `Theme.nightcap.headlineSize` (`17 → 16` or `20`), migrate the remaining
  view-level off-ladder sizes (`9 → 10`, `11 → 10/12`, `14 → 13/16`, `15 → 16`,
  `30 → 31`), replace the 16 semantic `.font(.caption/.caption2)` sites with
  `HarfFont` / `scaledFont`, and replace the 4 `.foregroundStyle(.secondary)`
  sites in `SettingsView.swift` with `Color.ink3` / `Color.ink4`.
- **Ledger transition:** `Ledger.offLadderFontSize → 0`; semantic-font ledger
  `→ 0`; `.secondary` foreground ledger `→ 0`.
- **Tests:** `swift test`; render `--screenshots` in both `(en)` and `(de)` via
  the built `.app` bundle (see [`docs/LOCALIZATION.md`](LOCALIZATION.md)) to
  confirm the 372 pt popover does not clip after `9 → 10` / `11 → 12` / `15 → 16`
  adjustments.

### Phase 5 — Shape & Corner-Style Conformance (`continuousCornerStyle` → `0`)

- **Scope:** Remove `style: .continuous` from all 12 non-exempt container sites
  (`MenuRedesign.swift` ×9, `SettingsView.swift` ×1, `SleepWarningHUD.swift` ×2),
  leaving only `AppIconProvider.swift:65`. Add a named `2` pt `Radius` token
  (replacing the raw `2` at `MenuRedesign.swift:957`) and resolve
  `Radius.control` / `Radius.card` (`HarfTheme.swift:119-121`) — either
  tightening them onto Harf's `{0, 2, 4, pill}` ladder (`2` and `4` pt) or
  recording an explicit owner exception in
  [§3](#3-sanctioned-exceptions-and-exemption-protocol) — backed by a
  `HarfAdherenceTests` radius-literal check.
- **Ledger transition:** `Ledger.continuousCornerStyle: 12 → 0`
  (`Ledger.restingShadow` remains `0`).
- **Tests:** `swift test`; light/dark `--screenshots` inspection of menu cards,
  Settings sidebar selection, and `SleepWarningHUD`.

### Phase 6 — Brand-Green Budget, Contrast & `#A4CD39` vs `#7EAE3C` Resolution

- **Owner decision gate:** Resolve Option A (`#A4CD39` + `Color.ink1` primary CTA
  resting fill, `< 5%` green punctuation) vs Option B (sanctioned `#7EAE3C`
  Nightcap brand green; see [§2](#2-unresolved-brand-green-decision-a4cd39-vs-7eae3c)).
- **Unblocked fixes in the same phase:**
  1. Fix dark-mode contrast on the selected Settings sidebar row
     (`SettingsView.swift:60, 63, 69`), replacing fixed `Color.accentText`
     (`0x3D5A14`) on dark `paper2` with a theme-aware foreground token that meets
     WCAG AA in both `.aqua` and `.darkAqua`.
  2. Reduce `SleepWarningHUD.swift:24, 40` to a single green accent per surface
     (either the crescent glyph or the button, not both).
  3. If Option A changes the brand hex, update `HarfTheme.swift` and
     `IconRenderer.swift` together and regenerate `assets/` (`--icon assets`).
- **Tests:** Add a deterministic WCAG relative-luminance contrast test in
  `Tests/DecaffeinateTests/` asserting AA (`>= 4.5:1` text, `>= 3.0:1` UI
  boundary on `rule2`) across every `(ink/status/onGreen, paper/tint)` pair in
  both light and dark appearances.

### Phase 7 — Spacing Ladder Normalization

- **Scope:** Replace accidental raw spacing/padding literals (`SettingsView.swift:926`
  `.padding(8)` → `Space.s2`, ad hoc paddings in `SettingsView.swift` and
  `MenuRedesign.swift`) with `Space.s1`–`Space.s9`, and either align
  `Theme.nightcap` (`rowGap: 6`, `contentInset: 14`) and button vertical
  paddings (`6 / 9 / 11`) to `Space` or codify a narrow sub-grid optical-offset
  token set (`1, 2` pt hairline/baseline offsets) enforced by a
  `HarfAdherenceTests` padding/spacing check.
- **Tests:** `swift test` + light/dark `--screenshots` layout check.

### Phase 8 — Off-Tick Provenance Resolution & Preview Baseline Refresh

- **Scope:** Complete the deferred Phase 0 performance commitment recorded in
  [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) (lines 82–88) and
  [`Sources/Decaffeinate/Core/ProcessProvenanceResolver.swift`](../Sources/Decaffeinate/Core/ProcessProvenanceResolver.swift)
  (lines 34–38): decouple `ProcessProvenanceResolver` parent-chain / `sysctl` /
  `proc_pidinfo` walks from the synchronous 1 Hz `AppState.tick()` so steady-state
  ticks read pre-resolved `(pid, startTime)` snapshots, remove the temporary
  inaccuracy note in `docs/ARCHITECTURE.md`, and refresh committed
  `assets/preview/*.png` screenshots via `Decaffeinate --screenshots assets/preview`
  once Phases 3–7 land.
- **Tests:** `ProcessProvenanceTests` and `AppStateTests` proving zero
  `ProcessIntrospecting` walks occur on steady-state 1 Hz ticks when the active
  `(pid, startTime)` set is unchanged; full `swift test` and CI screenshot
  artifact review.

---

## Related Documentation

- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — `AppState` tick loop, `SleepOutlook` single-verdict projection, and concurrency model
- [`docs/LOCALIZATION.md`](LOCALIZATION.md) — `L10n` / `Bundle.module` string-table architecture and German layout testing
- [`docs/PREVIEW.md`](PREVIEW.md) — visual QA via `--preview` and `--screenshots` without calling `pmset`
- [`docs/ROADMAP.md`](ROADMAP.md) & [`docs/PLAN-NEXT.md`](PLAN-NEXT.md) — shipped release history and near-term project priorities
