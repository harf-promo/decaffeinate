<div align="center">

<img src="assets/icon-1024.png" width="128" alt="Decaffeinate icon" />

# Decaffeinate

### The first Mac utility built to make your Mac **sleep** — not stay awake.

**Decaffeinate tells you the truth about what's keeping your Mac awake, and gives you the power to put it to sleep — even when rogue apps, stray `caffeinate` processes, and background tabs refuse to let go.**

[![CI](https://github.com/harf-promo/decaffeinate/actions/workflows/ci.yml/badge.svg)](https://github.com/harf-promo/decaffeinate/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![No root](https://img.shields.io/badge/root-not%20required-brightgreen)
![No telemetry](https://img.shields.io/badge/telemetry-none-brightgreen)

</div>

---

## ☕️ → 💤 Why this exists

There are *dozens* of Mac apps that keep your computer awake. Amphetamine, Caffeine, KeepingYouAwake, `caffeinate` — a whole genre dedicated to **fighting sleep**.

There is almost nothing built for the opposite, far more common problem:

> You walked away. Your agent finished its task an hour ago. But your MacBook is still wide awake on the desk — fans spinning, battery draining, OLED aging — because *something* asked it to stay up and never let go.

This happens constantly in the age of agentic coding. You kick off a long job in **Claude Code**, Cursor, a big `xcodebuild`, a Docker build, or a download — these tools (rightly) hold a *power assertion* so the Mac doesn't sleep mid-work. The problem is what happens **after** the work is done: the assertion gets left behind, a terminal stays "busy," a browser tab keeps an audio line open, or you forgot a `caffeinate` running in some tab. macOS gives you **no built-in way** to see these, question them, or override them — short of force-quitting the app.

> On the very machine this was built on, a quick scan found **six** stray `caffeinate` processes silently holding the Mac awake. That's the problem, live.

**Decaffeinate is the firewall for sleep.** It watches every power assertion on your system, attributes each one to the real process behind it, and — when you've stepped away and nothing important is actually happening — **forces a clean, safe sleep** regardless of who's complaining.

---

## What makes it different

|                                  | Caffeine / Amphetamine / KeepingYouAwake | **Decaffeinate** |
| -------------------------------- | :--------------------------------------: | :--------------: |
| Keep the Mac **awake**           |                    ✅                     |   ✅ (optional)   |
| Make the Mac **sleep** on demand |                    ❌                     |        ✅         |
| Force sleep **after you're idle**, overriding rogue holds |          ❌                     |        ✅         |
| Show you **what's** keeping it awake (by process) |                 ❌                     |        ✅         |
| Allow / block individual apps (a sleep firewall) |                  ❌                     |        ✅         |
| Battery-floor + overheating safety guards |                ➖                     |        ✅         |
| Headless `--scan` from the terminal |                  ➖                     |        ✅         |

Keeping a Mac awake is a one-liner. **Knowing when it's safe to sleep — and making it happen without losing your work — is the hard, useful part.** That's the part we built.

---

## Features

### 🔎 The Truth Scanner
A live, honest list of every process holding your Mac awake — pulled straight from the kernel via `IOPMCopyAssertionsByProcess`, attributed to the real app, with the assertion type and name. No guessing.

### 💤 The Decaffeinate Engine *(the headline)*
When you've been idle past your threshold (default 10 min) and nothing important is happening, Decaffeinate puts the Mac to sleep with `pmset sleepnow` — overriding stale "keep awake" assertions. Perfect for the *"my agent finished, let the laptop rest"* moment.

### 🧱 The Sleep Firewall
New app trying to keep your Mac awake? Get a prompt: **Always Allow**, **Allow for 1 hour**, or **Block**. Build a whitelist of apps that are genuinely allowed to hold the line (Final Cut exports, big builds) and let everything else fall asleep.

### 🛟 Safety Rails
Decaffeinate refuses to sleep at a bad moment, and *forces* sleep at a dangerous one:
- **Pause** during active media/calls, Time Machine backups, and macOS updates.
- **Backpack Guard** — if the Mac is overheating (lid closed in a bag), drop every keep-awake hold and sleep immediately.
- **Battery Floor** — on battery below your floor, keep-awake overrides are released so you never wake to a dead laptop.

### ⚡️ Keep-Awake, when you actually want it
The opposite mode is one click away. Hold the Mac (and optionally the display) awake on purpose — with all the same safety rails watching your back.

### 🖥 Terminal-friendly
```sh
Decaffeinate --scan      # print exactly what's keeping this Mac awake
```

---

## Install

### Homebrew *(once a signed release is published)*
```sh
brew tap harf-promo/tap
brew install --cask decaffeinate
```

### Signed DMG
Download the notarized `Decaffeinate-<version>.dmg` from the
[Releases](https://github.com/harf-promo/decaffeinate/releases) page and drag it
to Applications.

> The full signing + notarization + release pipeline is built
> (`.github/workflows/release.yml`); publishing signed builds just needs an Apple
> Developer ID configured as repo secrets — see [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md).

### Build from source
Requires macOS 14+ and Xcode 16 / Swift 6.

```sh
git clone https://github.com/harf-promo/decaffeinate.git
cd decaffeinate
./Scripts/build-app.sh          # → build/Decaffeinate.app
open build/Decaffeinate.app
```

Or just run the scanner without installing anything:
```sh
swift run Decaffeinate --scan
```

---

## How it works (and why it's safe)

Decaffeinate is deliberately boring under the hood — that's the point of trusting it with your sleep button:

- **It reads power assertions** with the public IOKit API `IOPMCopyAssertionsByProcess`. The same data `pmset -g assertions` shows you, attributed to processes.
- **It detects idle time** with `CGEventSource` HID idle — the same signal macOS uses to dim your screen. It never sees *what* you type, only *how long ago* you last did.
- **It sleeps the Mac** by invoking `/usr/bin/pmset sleepnow` — the exact mechanism behind  > Apple menu → Sleep. The kernel performs a normal, safe sleep transition, so even apps holding "prevent idle sleep" are cleanly overridden.
- **It keeps awake** (optional) with a standard `IOPMAssertionCreateWithName` hold, released the moment it's no longer wanted.

**No kernel extension. No private APIs. No root. No network calls. No telemetry. No accounts.** Decaffeinate runs entirely in user space and reads only the system signals it needs to do its one job. Because it shells out to `pmset` and inspects system-wide process telemetry, it lives **outside** the App Store sandbox — distributed as open source you can read, build, and audit yourself. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full design.

---

## 🙌 Help build this — we're looking for you

Decaffeinate is **free, open source (MIT), and built in the open by [Harf Promo](https://github.com/harf-promo)** — and it's just getting started. We're giving it to the world because everyone with a Mac deserves to know the truth about their machine's sleep.

**We want collaborators.** If you care about Mac internals, power management, clean SwiftUI, or just hate waking up to a hot, dead laptop — there is real, high-impact work here with your name on it.

Areas where you can make a dent today:

| Area | What's needed | Good for |
| --- | --- | --- |
| 📦 **Distribution** | Developer-ID signing + notarization, a Homebrew cask, auto-update | DevOps / release engineers |
| 🧬 **Assertion attribution** | Trace `coreaudiod` / `runningboardd` holds back to the *real* owner (the browser tab, the music app) | IOKit / systems hackers |
| 🌡 **Deeper sensors** | SMC temperature & fan reads for a smarter Backpack Guard | Hardware-curious folks |
| 🎨 **Design** | A richer menu-bar icon set, the dashboard, onboarding | Designers |
| 🌍 **Localization** | Translations beyond English | Anyone, anywhere |
| 🧪 **Testing** | More coverage, a sleep-simulation harness | QA / test engineers |
| 📝 **Docs & advocacy** | Guides, blog posts, demo videos | Writers & creators |

👉 **Start here:** read [`CONTRIBUTING.md`](CONTRIBUTING.md), browse the [roadmap](docs/ROADMAP.md), and look for [`good first issue`](https://github.com/harf-promo/decaffeinate/labels/good%20first%20issue) labels. Open a discussion, file an idea, or just send a PR. First-timers are genuinely welcome — we'll help you land your first contribution.

> Star the repo if you want a Mac that sleeps when it should. It helps more people find it, and it tells us to keep building.

---

## Roadmap (highlights)

- [ ] Notarized DMG + Homebrew cask
- [ ] Smarter agentic detection ("sleep when the build/agent finishes")
- [ ] Per-app and per-time-of-day sleep schedules
- [ ] Sleep history & battery-saved insights
- [ ] Deeper assertion attribution (real owner behind shared daemons)
- [ ] SMC thermal/fan integration

Full list in [`docs/ROADMAP.md`](docs/ROADMAP.md).

---

## Credits & prior art

Decaffeinate stands on the shoulders of the Mac power-management community. Projects and write-ups that informed this work include
[Amphetamine](https://apps.apple.com/app/amphetamine/id937984704),
[KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake),
[Sleepless](https://github.com/Aboudjem/Sleepless),
[SleepBar](https://github.com/ddasy/SleepBar),
[PreventSleep](https://github.com/jesse-c/PreventSleep), and
[Macchiato](https://github.com/ObservedObserver/Macchiato).
Where they keep Macs awake, we set out to do the harder inverse.

## License

[MIT](LICENSE) © 2026 Harf Promo. Use it, fork it, ship it, sell it — just keep the notice.
