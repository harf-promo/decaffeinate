# Lid-closed, honestly

Decaffeinate is a sleep firewall that runs entirely in user space — no root,
no kexts, no private APIs. This page explains, plainly, what that means for
working with the lid closed: what the **Clamshell Assistant** (added in
v1.24) does, what it doesn't, and why.

## What clamshell mode actually is

macOS has its own, built-in way to run a MacBook with the lid closed: plug in
an external display, keep the Mac on AC power, and connect an external
keyboard and/or mouse, and the system will happily keep running — display
output routed entirely to the external monitor — while the lid stays shut.
This isn't a Decaffeinate feature; it's Apple's own **clamshell mode**, and
it's worked this way for about two decades.

The catch is the requirements. Miss any one of them — no external display, on
battery, no external input — and macOS falls back to its normal behavior:
close the lid, and it sleeps.

## What the Clamshell Assistant does

Menu → **Keep awake…** → **Use with lid closed…** opens a small panel that:

1. **Detects** whether this Mac has a lid at all (it skips entirely on a Mac
   mini / Studio / Pro — there's nothing to assist with).
2. **Checks**, live, whether the three clamshell requirements are currently
   met: an external display connected, AC power, and (best-effort) an
   external keyboard/mouse.
3. When they are, offers to **arm** Decaffeinate's existing keep-awake hold —
   the same one the menu's "Keep awake indefinitely" toggle already creates —
   so you can close the lid knowing the Mac won't idle-sleep out from under
   you.
4. When they aren't, tells you **exactly** what's missing, in plain language
   — "Plug in an external display," "Connect to power," "Connect a keyboard
   and mouse" — instead of a vague "not ready."
5. If there's no external display at all — the one requirement Decaffeinate
   can't help you route around — it offers a clearly-labeled fallback: **keep
   working with the screens off**. That's keep-awake plus turning the display
   off, and it only works with the **lid open**. Screens off is not the same
   as lid closed, and the panel says so.

Every one of those reads is a public, ordinary system call — the same
IORegistry / CoreGraphics / IOHID techniques third-party utilities have used
for years, no different in kind from how Decaffeinate already reads battery
state or power assertions. Arming a session doesn't add any new safety logic
either: the existing battery-floor and Backpack Guard rails that already
govern every Decaffeinate keep-awake hold apply here exactly as they always
have.

## What it does not do

The Clamshell Assistant does not, and cannot, make a Mac stay awake with the
lid closed **and no external display**. That combination — a genuinely
"headless," displayless clamshell session — is not something Apple exposes a
user-space API for. The only way to force it is the systemwide
`pmset disablesleep` flag, which:

- requires **root**,
- is **global and persistent** (it affects the whole system, not just this
  app, and doesn't clear itself), and
- needs real safety engineering to use responsibly — clearing itself on
  crash, on quit, with a dead-man's-switch fallback, so a bug can't strand a
  Mac awake in a closed bag indefinitely.

Decaffeinate's entire premise is that it never asks for privileges like that.
So today, it simply doesn't do this. That's not an oversight — it's the same
trust-boundary decision the rest of the app makes, applied consistently here
too. If that ever changes, it will be a clearly-flagged, separately-explained,
opt-in addition — never something that quietly rides along with an update.

For the technical detail — which private APIs were tried and empirically
fail, and why only `disablesleep` actually works — see the "Non-goals &
negative knowledge" and "Lid-closed: the zero-root Clamshell Assistant"
sections of [`docs/ARCHITECTURE.md`](ARCHITECTURE.md).
