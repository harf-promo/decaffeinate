# Automation & agent integration

Decaffeinate is scriptable and hookable — everything the menu does has a
headless equivalent, so you can wire it into shell scripts, CI, and AI-agent
sessions. No daemon, no root, no MCP server to run: just the CLI (and the
`decaffeinate://` URL scheme).

## CLI verbs

```sh
Decaffeinate --status               # one human line: free to sleep, or held by N apps
Decaffeinate --status --json        # machine-readable status (for scripts / hooks)
Decaffeinate --why-awake            # same as --scan; add --json for structured output
Decaffeinate --scan                 # what's keeping this Mac awake, in detail
Decaffeinate --provenance           # …traced to the window / agent / project
Decaffeinate --sleep-now            # sleep now (exit non-zero if it couldn't launch)
Decaffeinate --display-off          # turn the display off, keep the system running
Decaffeinate --keep-awake 60        # hold awake 60 min (honours the safety rails), then release
Decaffeinate --diagnose             # settings + rules + scan, for a bug report
```

`--status --json` shape (stable, sorted keys):

```json
{
  "version": "1.17.0",
  "generatedAt": "2026-07-07T08:33:36Z",
  "onBattery": true,
  "batteryPercent": 80,
  "idleSeconds": 44,
  "thermal": "nominal",
  "uptimeSeconds": 432000,
  "holdingSystemSleep": 2,
  "blockers": [
    { "app": "Chrome", "reason": "Playing audio", "type": "PreventUserIdleSystemSleep",
      "realOwner": null, "heldSeconds": 3120, "pid": 100, "blocksSystemSleep": true }
  ]
}
```

## URL scheme

```sh
open "decaffeinate://sleep-now"
open "decaffeinate://keep-awake?minutes=90"
open "decaffeinate://stop-awake"
```

## Agent hooks (Claude Code, Codex, …)

The most common ask in the agentic era is *"let my Mac sleep once the agent is
done."* Decaffeinate already does this automatically — it watches a recognised
agent's `caffeinate -w` hold and offers one-click **"Sleep when it finishes"**
(or auto-arms it, if you enable that in Settings → Automation). So for most
people **no hook is needed** — just leave Decaffeinate running.

If you want an explicit hook — e.g. to force sleep the moment a long unattended
job ends — add a **Stop hook** that calls the CLI. For Claude Code, in
`~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command",
        "command": "/Applications/Decaffeinate.app/Contents/MacOS/Decaffeinate --sleep-now" } ] }
    ]
  }
}
```

> ⚠️ This sleeps the Mac at the **end of every turn**, so it's best for a truly
> unattended overnight run, not interactive work. For interactive sessions,
> prefer Decaffeinate's built-in idle-aware auto-sleep (which only sleeps once
> *you've* also stepped away), or gate the hook on `--status --json`'s
> `idleSeconds` in a small wrapper script.

A gated wrapper (`sleep-if-idle.sh`) that only sleeps when you're also away:

```sh
#!/bin/sh
DECAF="/Applications/Decaffeinate.app/Contents/MacOS/Decaffeinate"
idle=$("$DECAF" --status --json | /usr/bin/plutil -extract idleSeconds raw - 2>/dev/null || echo 0)
[ "${idle:-0}" -ge 300 ] && "$DECAF" --sleep-now
```

## On the roadmap

- A first-class **hook installer** (`--install-hook` / `--uninstall-hook`) with a
  clean, marker-based uninstall, and an **MCP server** so an agent can request a
  hold or a "sleep when I finish" directly. Tracked in
  [`ROADMAP.md`](ROADMAP.md).
