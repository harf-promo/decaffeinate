# Decaffeinate vs. KeepingYouAwake

[KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) is a small,
well-loved, open-source menu-bar app with one job: hold your Mac awake with a
single click, using the same public `caffeinate`-style assertion API
Decaffeinate itself uses for its own (secondary) keep-awake mode. It's simple,
free, and does that one thing well — no lid-closed mode, no per-app rules, no
force-sleep.

**Decaffeinate** shares its "one clear job, done honestly, no telemetry"
spirit — but the job is the opposite one:

| | KeepingYouAwake | Decaffeinate |
| --- | :---: | :---: |
| Keep the Mac awake, one click | ✅ | ✅ (secondary, opt-in) |
| Show **what's already** holding the Mac awake | ❌ | ✅ — attributed to the real app, with a plain-English reason |
| **Force sleep** past a rogue or stray hold | ❌ | ✅ |
| Auto-sleep after idle | ❌ | ✅ |
| Per-app allow / block rules | ❌ | ✅ |
| Agent-aware ("sleep when my build/AI agent finishes") | ❌ | ✅ |
| Open source | ✅ | ✅ (MIT) |
| Telemetry | None | None |

If you just want a lightweight, one-click "stay awake" toggle, KeepingYouAwake
is a great, minimal choice — and one of the projects that inspired
Decaffeinate's own honesty-first design (see the
[Credits](../../README.md#credits--prior-art)). Decaffeinate exists for the
much more common moment: you *didn't* click anything, and the Mac is awake
anyway.
