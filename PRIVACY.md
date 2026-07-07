# Privacy Policy

Decaffeinate is built to be trusted with your sleep button, so its privacy
posture is deliberately boring: **everything stays on your Mac.**

## The short version

- **No telemetry. No analytics. No accounts. No tracking.** Decaffeinate never
  sends any usage data, identifiers, or crash reports anywhere.
- **The only network request** is the optional [Sparkle](https://sparkle-project.org)
  update check, which fetches a signed `appcast.xml` from this project's GitHub
  releases. Turn updates off (Settings → About) and Decaffeinate makes **zero**
  network requests.
- **No data ever leaves your device.** There is no server, no cloud, no
  third-party SDK.

## What Decaffeinate reads, and why

All of these are read locally, in memory, to do the app's one job — and none of
them are transmitted, logged off-device, or persisted beyond what's noted:

| What | How | Why |
| --- | --- | --- |
| Power assertions (which apps hold the Mac awake) | `IOPMCopyAssertionsByProcess` (public IOKit) | To show you what's keeping your Mac awake. |
| Idle time (how long since the last input) | `CGEventSource` — **duration only, never keystrokes or content** | To know when you've stepped away. |
| Process names / command lines / working directory of sleep-holders | public `libproc` / `sysctl` | To trace a hold back to its window / agent / project. |
| Battery, power source, thermal state | `IOPSCopyPowerSourcesInfo`, `ProcessInfo.thermalState` | Safety rails (battery floor, backpack guard). |
| Audio device names | CoreAudio | To label an audio hold ("AirPods Pro"). |

Decaffeinate **never** reads keystroke content, screen contents, other
processes' memory, your files, your location, or your network traffic.

## What Decaffeinate stores, and where

A few small preferences and logs live **only** in your local macOS
`UserDefaults` (and never leave your Mac):

- Your settings and per-app sleep rules.
- A rolling, capped on-device history of forced sleeps and the Mac's rest rhythm
  (used for the Rest & Restart and History views).
- The timestamp of the last update check.

You can clear the histories any time (Settings → History / Rest & Restart), and
uninstalling with `brew uninstall --cask decaffeinate --zap` removes them.

## Permissions

Decaffeinate runs entirely in user space — **no root, no kernel extension, no
private APIs**. It may ask for notification permission (optional) so it can tell
you when a new app starts holding your Mac awake or when it puts the Mac to
sleep; you can decline and everything else still works.

## Changes

Any change to this policy will appear in this file's git history and the
[CHANGELOG](CHANGELOG.md). Questions? Open a discussion on the
[repository](https://github.com/harf-promo/decaffeinate).
