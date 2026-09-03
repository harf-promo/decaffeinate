<!-- fleet-template: v1 | reconciled-against: fleet-kit/templates/AGENT-CONTEXT-TEMPLATE.md @ 35354d0 2026-09-02 -->
# AGENTS.md — Decaffeinate

## What this repo is

Decaffeinate is a macOS menu-bar app — a *sleep firewall*. It shows exactly what's
holding the Mac awake (IOKit power assertions, attributed to the responsible process
via `IOPMCopyAssertionsByProcess`) and can force an idle Mac to sleep with `pmset
sleepnow`. Keep-awake is a secondary, opt-in mode — it does **not** wrap
`caffeinate`. Public repo `harf-promo/decaffeinate`, distributed as a notarized DMG
and a Homebrew cask.

## Stack & layout

Swift 6 (`swift-tools-version: 6.0`), SwiftPM, macOS 14+. Two executable targets are
defined in `Package.swift`:

- **`Decaffeinate`** — the real app. Depends on three third-party SwiftPM packages:
  Sparkle (auto-update), KeyboardShortcuts (AppKit-only global hotkeys), and `MCP`
  (`modelcontextprotocol/swift-sdk`, for the opt-in MCP server — see
  `docs/AUTOMATION.md`). All three need macOS-native toolchain to resolve or build
  (see Host boundaries below).
- **`DecaffeinateLidHelper`** — an **unintegrated spike target**
  (`docs/PHASE-B-SPIKE.md`). Verified directly against `Package.swift`: the main
  `Decaffeinate` target does not depend on it, import it, or invoke it from any
  UI/menu/CLI path. It exists solely so a privileged-helper mechanism (a root-only
  `pmset disablesleep` path) compiles and is unit-tested via fakes — its real
  pmset/XPC/SMAppService calls are never executed. If this changes, say so plainly;
  don't describe it as wired in unless a real dependency edge exists.

Layout:

- `Sources/Decaffeinate/{Core,Models,Views}` — app code; `Resources/{en,de}.lproj` —
  localized string tables, copied into `Bundle.module` at build time via
  `defaultLocalization` (see `docs/LOCALIZATION.md`)
- `Sources/DecaffeinateLidHelper/` — the spike target above
- `Tests/DecaffeinateTests/` (481 tests) + `Tests/DecaffeinateLidHelperTests/` (21
  tests) — 502 total, reconfirmed this session via `swift test list`
- `Scripts/` — release tooling: `version.sh` (derives CFBundleVersion: major×1_000_000
  + minor×1_000 + patch — do **not** reintroduce `GITHUB_RUN_NUMBER` coupling),
  `build-app.sh` (produces the `.app` bundle), `make-dmg.sh`, `generate-icon.sh`
- `Casks/decaffeinate.rb` — the **canonical copy** of the Homebrew cask; the live tap
  is the separate repo `harf-promo/homebrew-tap`, mirrored automatically by
  `release.yml` on a tag push
- `docs/` — `ARCHITECTURE.md`, `DISTRIBUTION.md`, `LOCALIZATION.md`, `LID-CLOSED.md`,
  `PHASE-B-SPIKE.md`, `PREVIEW.md`, `AUTOMATION.md`, `ROADMAP.md`, `PRESS-KIT.md`,
  `HOMEBREW-CORE.md`, `WIDGET-SPIKE.md`, `PLAN-NEXT.md`
- `.github/workflows/ci.yml` (build + test + `swift-format` lint + cask style, on
  push/PR to `main`) and `release.yml` (sign/notarize/publish DMG + cask bump, on a
  `v*` tag push)

## Commands

Every command below is grounded in `.github/workflows/ci.yml` or re-verified directly
this session (`swift build` and `swift test list` both ran clean on this Mac):

```bash
swift build              # debug build (~6-10 s warm)
swift build -c release   # release build
swift test                 # full XCTest suite — 502 tests
                             # (481 DecaffeinateTests + 21 DecaffeinateLidHelperTests)
swift format lint --strict --recursive --configuration .swift-format Sources Tests Package.swift
                             # CI lint gate
brew style Casks/decaffeinate.rb   # cask sanity — also a CI gate
swift run Decaffeinate --scan       # headless power-assertion scan — CI smoke test
./Scripts/build-app.sh               # produce the .app bundle — also a CI step
```

**Release flow** (tag-triggered, `release.yml`):

1. Bump the marketing version — see `Scripts/version.sh`'s header comment for the
   CFBundleVersion formula.
2. Push a `v*` tag. CI builds, signs, notarizes, and publishes the DMG +
   `SHA256SUMS.txt` + a signed Sparkle appcast to the GitHub Release; bumps this
   repo's own `Casks/decaffeinate.rb`; and mirrors the cask into
   `harf-promo/homebrew-tap` (skips that last step loudly, via a workflow warning, if
   `TAP_REPO_TOKEN` isn't configured — see `docs/DISTRIBUTION.md`).

## Verification before done

1. `swift build && swift test` clean.
2. `swift format lint --strict --recursive --configuration .swift-format Sources Tests
   Package.swift` clean — CI enforces this on every push/PR, don't skip it locally.
3. Visual QA **without sleeping the Mac**: `swift run Decaffeinate --preview` or
   `--screenshots <dir>` (fixture data — Sleep Now, display-off, and keep-awake never
   call `pmset` in these modes; see `docs/PREVIEW.md`). Do not click Sleep Now on the
   installed `/Applications` build unless you actually want this Mac to sleep.
4. A change touching `Sources/DecaffeinateLidHelper/` gets its own test run
   (`swift test --filter DecaffeinateLidHelperTests`) but must stay out of the live
   `Decaffeinate` target's build graph, menu, and CLI surface — wiring the spike in
   for real would silently turn it into a shipped root-adjacent feature (see Stack &
   layout, and the hard constraints in `docs/PHASE-B-SPIKE.md`).

"Done" here means build + full test suite + lint all green, plus an actual
`--preview`/`--screenshots` look at any change touching `Sources/Decaffeinate/Views/`
— never "tests pass" alone for something with a visible UI surface.

## Guardrails

**Tier: unguarded** — absent from `~/.claude/hooks/billed_repos.json`, checked
directly rather than assumed. Public repo, no branch protection on `main` (confirmed
via `gh api repos/harf-promo/decaffeinate/branches/main/protection` → 404 "Branch not
protected"). Direct push to `main` is technically fine on this repo; see Git & PR flow
below for the convention this session is following anyway.

- **Never reintroduce `GITHUB_RUN_NUMBER` into the CFBundleVersion formula** —
  `Scripts/version.sh`'s own header comment forbids this explicitly; it was a real
  regression once.
- `release.yml`'s preflight step treats `SPARKLE_PRIVATE_KEY` as exactly as
  load-bearing as the code-signing secrets: a release published without a
  regenerated Sparkle appcast silently breaks auto-update for every installed copy.
  Never work around or skip that preflight check.
- `Casks/decaffeinate.rb` in this repo is a **canonical copy, not the live cask** —
  the tap Homebrew actually reads is `harf-promo/homebrew-tap`. `release.yml` bumps
  both automatically on a tag push; don't hand-edit only the copy in this repo and
  assume the tap picked it up.
- `DecaffeinateLidHelper` must stay unintegrated (see Stack & layout) — never add a
  dependency edge from the `Decaffeinate` target onto it, and never call its real
  pmset/XPC/SMAppService paths outside of tests, per `docs/PHASE-B-SPIKE.md`'s hard
  safety constraints.
- No payment, auth, or RLS surface exists anywhere in this repo — it's a local
  menu-bar utility with no backend. The one path that matters operationally is the
  signing/notarization/auto-update chain covered above. There is no
  `.orchestration/lanes.yml` in this repo (confirmed by listing, not assumed) — so
  there are no `hot_files`/`deploy_on_merge` entries to duplicate here.

## Git & PR flow

Public repo, not in the guarded-repo map, no branch protection on `main` — direct
push is fine and has been this repo's standing convention (CI runs the same
`ci.yml` gate either way; Actions minutes are unlimited on a public repo). No
repo-specific shipper exists for `decaffeinate`. This session opened a PR anyway for
reviewability rather than pushing straight to `main`, matching this fleet's general
preference for a checkable diff on anything beyond a trivial one-line fix — use
`/ship` for a future change if a branch → PR → squash-merge flow is wanted, or push
directly when a PR would add no real review value (e.g. a version-bump-only commit).

## Host boundaries — VPS vs Mac

**This is Mac-only work by structural necessity for anything that builds, tests, or
runs the app.** `swift build` / `swift test` / `swift run` all need Xcode's toolchain
and the macOS 14+ SDK; three SwiftPM dependencies compound this — Sparkle (embeds and
links a signed `.framework`), KeyboardShortcuts (AppKit-only), and the MCP
`swift-sdk` package — none of which resolve or build meaningfully on Linux.
`Scripts/build-app.sh`, `make-dmg.sh`, and the whole `release.yml` signing/
notarization chain additionally need `codesign`, `xcrun notarytool`, and a real
Developer ID keychain — Apple-only tooling with no Linux equivalent, not even
emulated.

This repo is **also** being cloned to the VPS, at
`/opt/codeagents/projects/decaffeinate` (`codeagents` user on `wikiclaw-1`) — but that
clone is for **docs/read-only work only**, mirroring Harf Media's existing
split-scope pattern (`fleet-command/PORTFOLIO.md`): reading source to answer
questions, and editing docs/`AGENTS.md`/`CHANGELOG.md`/`README.md`, are fine there. A
VPS-side agent working in this repo should **never** attempt `swift build`,
`swift test`, `swift run`, or any `Scripts/*.sh` invocation — expect those to fail
informatively (no Xcode toolchain on Linux), and route any real build/test/run/
release need back to the Mac rather than trying to work around the gap.

## Orca conventions

- Update the worktree comment at meaningful checkpoints:
  `orca-ide worktree set --worktree active --comment "<status>" --json`
- Set `--workspace-status in-review` when a PR opens on this repo's work.
- A dispatched worker sends `worker_done` exactly once, with an explicit
  `--outcome`, when finishing supervised orchestration work here — see
  fleet-command's `ORCHESTRATION.md` for the full coordinator recipe.

## Where to find more

| Topic | File |
| --- | --- |
| Full architecture | `docs/ARCHITECTURE.md` |
| Signing/notarization/release setup | `docs/DISTRIBUTION.md` |
| Adding or editing a localization | `docs/LOCALIZATION.md` |
| Clamshell / lid-closed assistant — honest scope | `docs/LID-CLOSED.md` |
| `DecaffeinateLidHelper` spike — hard safety constraints | `docs/PHASE-B-SPIKE.md` |
| Preview/screenshot mode without sleeping the Mac | `docs/PREVIEW.md` |
| CLI verbs, hooks, MCP server, `decaffeinate://` scheme | `docs/AUTOMATION.md` |
| Roadmap | `docs/ROADMAP.md` |
| Press kit | `docs/PRESS-KIT.md` |
| homebrew/cask-core submission readiness | `docs/HOMEBREW-CORE.md` |
| Widget spike (historical) | `docs/WIDGET-SPIKE.md` |
| Current short-term plan | `docs/PLAN-NEXT.md` |
| Fleet-wide guarded-repo tier map | `~/.claude/hooks/billed_repos.json` |
| Fleet sweep / doctor reporting | `fleet-command/PORTFOLIO.md`, `fleet-command/SWEEP.md` |

No nested `AGENTS.md`/`CLAUDE.md` files exist elsewhere in this repo — confirmed by a
direct listing. Root `CLAUDE.md` stays the 11-byte `@AGENTS.md` stub; only Claude Code
follows that import, so this file (not `CLAUDE.md`) is what Codex, Gemini, Cursor, and
Antigravity read directly.

## Fleet context

This file follows the fleet-wide template
(`fleet-kit/templates/AGENT-CONTEXT-TEMPLATE.md`, stamped above). Config drift between
this file and the template is caught automatically by `fleet-doctor.sh`, which runs as
part of fleet-command's daily sweep — see that repo's `PORTFOLIO.md` and `SWEEP.md` for
what gets reported and what (if anything) gets auto-dispatched.
