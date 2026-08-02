# Decaffeinate vs. Amphetamine

Both are excellent Mac utilities for controlling sleep. They solve almost
opposite problems.

**Amphetamine** (Mac App Store, free with IAP) is the best app for keeping a
Mac **awake** on purpose — session presets, triggers, and a well-regarded
**Closed-Display Mode** for working with the lid shut when a display and power
are connected. If your problem is "I need my Mac to stay up," Amphetamine is a
mature, well-maintained answer.

**Decaffeinate** is built for the opposite, more common problem: **your Mac
should have gone to sleep and didn't.** A stray `caffeinate` process, a
forgotten browser tab, an AI agent that finished an hour ago — something is
quietly holding your Mac awake, and nothing shows you who or lets you overrule
it.

| | Amphetamine | Decaffeinate |
| --- | :---: | :---: |
| Keep the Mac awake on purpose | ✅ (its core job) | ✅ (secondary, opt-in) |
| Show **every process** currently holding sleep, by name | ❌ | ✅ |
| **Force sleep** past a rogue hold | ❌ | ✅ |
| Auto-sleep after idle, overriding stale holds | ❌ | ✅ |
| Closed-Display Mode (lid closed + external display) | ✅ | ✅ (Clamshell Assistant, v1.24+) |
| Lid-closed with **no** external display | Claims a "publicly-accessible API" (unverified mechanism, reported fragile on Apple Silicon) | ❌ — honestly, that needs root ([why](../LID-CLOSED.md)) |
| Distribution | Mac App Store (sandboxed) | Signed DMG + Homebrew (non-sandboxed — needs `pmset` + system telemetry) |
| Price | Free / IAP | Free |
| Open source | ❌ | ✅ (MIT) |

If you want your Mac to **stay awake**, Amphetamine is a great, mature choice.
If your problem is a Mac that **won't fall asleep when it should**, that's
what Decaffeinate was built for — see the [README](../../README.md) for the
full story.
