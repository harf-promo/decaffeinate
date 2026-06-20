# Changelog

All notable changes to Decaffeinate are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
